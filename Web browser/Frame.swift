//
//  Frame.swift
//  Web browser
//
//  A named collection of sites — one ring's worth. You can keep several and
//  switch between them.
//

import Foundation

struct Frame: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var sites: [Site]
    /// Whoever put the frame together — you, by default, or the Are.na account
    /// a channel was pulled from. Travels with the frame through export and
    /// import, so a frame passed around says where it came from. Optional
    /// because frames saved before this existed don't have one.
    var author: String?

    init(id: UUID = UUID(), name: String, sites: [Site] = [], author: String? = nil) {
        self.id = id
        self.name = name
        self.sites = sites
        self.author = author
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled frame" : name
    }

    /// The author, if one was recorded and isn't just empty space.
    var displayAuthor: String? {
        guard let author else { return nil }
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Filename-safe version of the name.
    var slug: String {
        let cleaned = displayName
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()

        // Collapse runs of hyphens.
        let parts = cleaned.split(separator: "-", omittingEmptySubsequences: true)
        return parts.joined(separator: "-")
    }
}
