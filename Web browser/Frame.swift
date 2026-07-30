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

    init(id: UUID = UUID(), name: String, sites: [Site] = []) {
        self.id = id
        self.name = name
        self.sites = sites
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled frame" : name
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
