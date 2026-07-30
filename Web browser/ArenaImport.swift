//
//  ArenaImport.swift
//  Web browser
//
//  Turning an Are.na channel into a frame. Only the links come across — text,
//  images and nested channels have nowhere to go on a ring of favicons.
//

import AppKit

/// Just enough of the Are.na v3 API to read a channel's links.
private enum Arena {
    static let host = "https://api.are.na/v3/channels"
    /// Are.na answers 403 to a request with no User-Agent.
    static let agent = "around-the-wwworld"
    /// Blocks per request, the most the API will give at once.
    static let perPage = 100
    /// Enough for 10,000 blocks. A stop, so a surprise from the API can't leave
    /// this paging forever.
    static let maxPages = 100

    struct Channel: Decodable {
        struct Owner: Decodable {
            let name: String?
            let slug: String?
        }

        let title: String?
        let owner: Owner?
    }

    /// Are.na names carry zero-width spaces — "Elliott<ZWSP>Cost" — which show
    /// up as odd gaps anywhere the name is drawn.
    static func tidy(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .components(separatedBy: CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}"))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    struct Contents: Decodable {
        struct Meta: Decodable {
            let hasMorePages: Bool?
        }

        struct Block: Decodable {
            struct Source: Decodable { let url: String? }
            struct Description: Decodable { let plain: String? }

            let type: String?
            let title: String?
            let source: Source?
            let description: Description?
        }

        let meta: Meta
        let data: [Block]
    }

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ArenaError.badStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

enum ArenaError: LocalizedError {
    case notAChannel
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notAChannel:
            "That doesn't look like an Are.na channel address."
        case .badStatus(404):
            "There's no channel at that address, or it isn't public."
        case .badStatus(let code):
            "Are.na answered with \(code)."
        }
    }
}

extension BrowserModel {
    /// The channel slug out of whatever was pasted: a full are.na address, an
    /// api.are.na one, or the slug on its own.
    static func arenaSlug(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.contains("/") else { return trimmed }   // already a slug
        guard let url = URL.normalized(from: trimmed),
              url.host()?.contains("are.na") == true else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // api.are.na/v3/channels/<slug>, and are.na/<user>/<slug>.
        if let mark = parts.firstIndex(of: "channels"), mark + 1 < parts.count {
            return parts[mark + 1]
        }
        return parts.count >= 2 ? parts[1] : parts.first
    }

    /// Every link in the channel, in the order Are.na hands them over, with each
    /// block's description kept as the site's notes.
    private func arenaSites(inChannel slug: String) async throws -> [Site] {
        guard let root = URL(string: "\(Arena.host)/\(slug)/contents") else {
            throw ArenaError.notAChannel
        }

        var sites: [Site] = []
        var known: Set<String> = []
        var page = 1

        while page <= Arena.maxPages {
            guard var components = URLComponents(url: root, resolvingAgainstBaseURL: false) else { break }
            components.queryItems = [URLQueryItem(name: "per", value: "\(Arena.perPage)"),
                                     URLQueryItem(name: "page", value: "\(page)")]
            guard let url = components.url else { break }

            let contents = try await Arena.fetch(Arena.Contents.self, from: url)

            for block in contents.data where block.type == "Link" {
                guard let address = block.source?.url, !address.isEmpty else { continue }

                let site = Site(name: block.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                url: address,
                                notes: block.description?.plain?.isEmpty == false
                                       ? block.description?.plain : nil)

                // The same site twice on a ring would just be two identical
                // squares, so the second is dropped.
                guard let identity = site.identity, !known.contains(identity) else { continue }
                known.insert(identity)
                sites.append(site)
            }

            guard contents.meta.hasMorePages == true, !contents.data.isEmpty else { break }
            page += 1
        }
        return sites
    }

    /// Ask for a channel, then bring its links in as a frame of their own.
    func importArenaChannel() {
        let field = NSTextField.addressField(placeholder: "https://www.are.na/user/channel")

        let prompt = NSAlert()
        prompt.messageText = "Load Are.na Channel"
        prompt.informativeText = "Paste a channel address. Its links become a frame; anything else in the channel is left behind."
        prompt.addButton(withTitle: "Load")
        prompt.addButton(withTitle: "Cancel")
        prompt.accessoryView = field
        prompt.window.initialFirstResponder = field

        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        guard let slug = Self.arenaSlug(from: field.stringValue) else {
            alert = BrowserAlert(title: "Couldn't Load Channel",
                                 message: ArenaError.notAChannel.localizedDescription)
            return
        }

        Task { @MainActor in
            do {
                // The channel itself, for its name; a channel with no title
                // falls back to the slug it was asked for by.
                let channel = try await Arena.fetch(Arena.Channel.self,
                                                    from: URL(string: "\(Arena.host)/\(slug)")!)
                let sites = try await arenaSites(inChannel: slug)

                guard !sites.isEmpty else {
                    alert = BrowserAlert(title: "Nothing to Load",
                                         message: "That channel has no links in it.")
                    return
                }

                // Signed with whoever's channel it is, rather than with you.
                let name = Arena.tidy(channel.title) ?? slug
                let author = Arena.tidy(channel.owner?.name) ?? Arena.tidy(channel.owner?.slug)
                addFrame(named: name, sites: sites, author: author)
                if let added = frames.last { select(added) }
            } catch {
                alert = BrowserAlert(title: "Couldn't Load Channel",
                                     message: error.localizedDescription)
            }
        }
    }
}
