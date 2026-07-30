//
//  Site.swift
//  Web browser
//
//  Created by Elliott Cost on 1/19/26.
//

import Foundation

extension URL {
    /// Builds a URL from whatever was typed, assuming https when no scheme is
    /// given. Shared by bookmarks and the URL bar so both behave the same.
    static func normalized(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        return URL(string: "https://" + trimmed)
    }
}

struct Site: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var url: String
    /// Which square on the ring this sits in. Explicit rather than implied by
    /// array order, so sites can be spaced out with empty squares between them.
    /// nil means "not placed yet"; the store assigns one.
    var slot: Int?
    /// Overrides the colour normally derived from the domain, so a letter
    /// square's colour can be re-rolled and stick. nil means "use the domain".
    var colorSeed: UInt64?
    /// Whatever you want to remember about this site. Travels with the frame,
    /// including through export and import.
    var notes: String?

    init(id: UUID = UUID(), name: String, url: String, slot: Int? = nil,
         colorSeed: UInt64? = nil, notes: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.slot = slot
        self.colorSeed = colorSeed
        self.notes = notes
    }

    /// The URL to load, tolerating input typed without a scheme ("example.com").
    var resolvedURL: URL? {
        URL.normalized(from: url)
    }

    var host: String {
        guard let host = resolvedURL?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Display name, falling back to the host when the user left it blank.
    var displayName: String {
        name.isEmpty ? host : name
    }

    /// Letter drawn in the square when no favicon could be found. Always taken
    /// from the domain, so sohyeon.online reads "S" whatever you named it.
    var monogram: String {
        host.first.map { String($0).uppercased() } ?? "?"
    }
}
