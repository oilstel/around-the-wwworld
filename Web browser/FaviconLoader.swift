//
//  FaviconLoader.swift
//  Web browser
//
//  Fetches a site's favicon by asking the site itself: parse <link rel="icon">
//  out of the page head, fall back to /favicon.ico and /apple-touch-icon.png.
//  Results are cached in memory and on disk so the frame paints instantly on
//  relaunch.
//

import AppKit
import Combine

@MainActor
final class FaviconLoader: ObservableObject {
    static let shared = FaviconLoader()

    /// Bumped by `refreshAll()` so views re-run their fetch task.
    @Published private(set) var generation = 0

    private var memoryCache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    func icon(for site: Site) async -> NSImage? {
        guard let pageURL = site.resolvedURL else { return nil }
        let key = site.host

        if let cached = memoryCache[key] { return cached }

        if let existing = inFlight[key] { return await existing.value }

        let fileURL = cacheFile(for: key)
        if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
            memoryCache[key] = image
            return image
        }

        let task = Task<NSImage?, Never> {
            let data = await FaviconFetcher.fetch(pageURL: pageURL)
            guard let data, let image = NSImage(data: data), image.isValidIcon else { return nil }
            try? data.write(to: fileURL)
            return image
        }
        inFlight[key] = task

        let image = await task.value
        inFlight[key] = nil
        if let image { memoryCache[key] = image }
        return image
    }

    /// Throw away every cached icon and re-fetch on the next pass.
    func refreshAll() {
        memoryCache.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        generation += 1
    }

    func forget(_ site: Site) {
        let key = site.host
        memoryCache[key] = nil
        inFlight[key]?.cancel()
        inFlight[key] = nil
        try? FileManager.default.removeItem(at: cacheFile(for: key))
    }

    private func cacheFile(for host: String) -> URL {
        let safe = host.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appendingPathComponent(safe).appendingPathExtension("icon")
    }
}

private extension NSImage {
    /// NSImage happily returns a zero-sized object for a 404 HTML page.
    var isValidIcon: Bool {
        size.width >= 1 && size.height >= 1 && !representations.isEmpty
    }
}

// MARK: - Fetching

enum FaviconFetcher {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    static func fetch(pageURL: URL) async -> Data? {
        var candidates: [URL] = []

        if let (html, finalURL) = await loadHTML(from: pageURL) {
            candidates += iconLinks(in: html, base: finalURL)
        }

        // Every site gets the well-known locations tried as a backstop.
        if var root = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
            root.path = "/favicon.ico"
            root.query = nil
            root.fragment = nil
            if let url = root.url { candidates.append(url) }
            root.path = "/apple-touch-icon.png"
            if let url = root.url { candidates.append(url) }
        }

        var seen = Set<URL>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if let data = await loadImageData(from: candidate) { return data }
        }
        return nil
    }

    private static func loadHTML(from url: URL) async -> (html: String, base: URL)? {
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        // The head is all we need; don't decode a multi-megabyte page.
        let head = data.prefix(200_000)
        guard let html = String(data: head, encoding: .utf8)
                ?? String(data: head, encoding: .isoLatin1) else { return nil }
        return (html, response.url ?? url)
    }

    private static func loadImageData(from url: URL) async -> Data? {
        if url.scheme == "data" { return decodeDataURI(url) }
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        guard !data.isEmpty, NSImage(data: data)?.isValidIcon == true else { return nil }
        return data
    }

    private static func decodeDataURI(_ url: URL) -> Data? {
        let text = url.absoluteString
        guard let comma = text.firstIndex(of: ",") else { return nil }
        let payload = String(text[text.index(after: comma)...])
        if text[..<comma].contains("base64") {
            return Data(base64Encoded: payload)
        }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }

    static func html(from url: URL) async -> (html: String, base: URL)? {
        await loadHTML(from: url)
    }

    // MARK: Parsing

    private static let linkTagRegex = try! NSRegularExpression(
        pattern: "<link\\s[^>]*>", options: [.caseInsensitive])

    /// Icon `<link>` hrefs from the page head, best candidate first. A site's
    /// own favicon wins over its apple-touch-icon — the touch icon is usually
    /// a padded, rounded version made for a home screen, not the mark the site
    /// actually identifies itself by.
    static func iconLinks(in html: String, base: URL) -> [URL] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var scored: [(url: URL, isAppleTouch: Bool, closeness: Int)] = []

        for match in linkTagRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])

            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.contains("icon"),
                  !rel.contains("mask-icon"),   // monochrome Safari pinned-tab glyph
                  let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL
            else { continue }

            let isAppleTouch = rel.contains("apple-touch")
            let declared = declaredSize(in: tag)
            let effective = declared > 0 ? declared : (isAppleTouch ? 180 : 32)
            // Within each kind, prefer whatever is closest to a comfortable
            // 128pt render size.
            scored.append((url, isAppleTouch, -abs(effective - 128)))
        }

        return scored
            .sorted { first, second in
                if first.isAppleTouch != second.isAppleTouch { return !first.isAppleTouch }
                return first.closeness > second.closeness
            }
            .map(\.url)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..<tag.endIndex, in: tag))
        else { return nil }

        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) {
                let value = String(tag[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// Largest dimension declared in `sizes="32x32 64x64"`, or 0 if absent.
    private static func declaredSize(in tag: String) -> Int {
        guard let sizes = attribute("sizes", in: tag)?.lowercased() else { return 0 }
        return sizes.split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Int($0.split(separator: "x").first ?? "") }
            .max() ?? 0
    }
}
