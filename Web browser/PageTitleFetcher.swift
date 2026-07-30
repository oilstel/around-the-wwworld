//
//  PageTitleFetcher.swift
//  Web browser
//
//  Pulls a page's <title> so adding a site doesn't mean typing a name.
//

import Foundation

enum PageTitleFetcher {
    private static let titleRegex = try! NSRegularExpression(
        pattern: "<title[^>]*>(.*?)</title>",
        options: [.caseInsensitive, .dotMatchesLineSeparators])

    static func title(of url: URL) async -> String? {
        guard let (html, _) = await FaviconFetcher.html(from: url) else { return nil }
        return parseTitle(in: html)
    }

    static func parseTitle(in html: String) -> String? {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = titleRegex.firstMatch(in: html, range: range),
              let captured = Range(match.range(at: 1), in: html) else { return nil }

        let title = String(html[captured])
            .decodingBasicHTMLEntities()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? nil : title
    }
}

private extension String {
    /// Just the handful that routinely show up in titles.
    func decodingBasicHTMLEntities() -> String {
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                        "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "—",
                        "&ndash;": "–", "&hellip;": "…"]
        return entities.reduce(self) { text, entity in
            text.replacingOccurrences(of: entity.key, with: entity.value, options: .caseInsensitive)
        }
    }
}
