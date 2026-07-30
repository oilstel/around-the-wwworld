//
//  BookmarksTransfer.swift
//  Web browser
//
//  Frames as plain JSON files, so one can be backed up or handed to someone
//  else — and theirs dropped straight onto your window.
//

import AppKit
import UniformTypeIdentifiers

/// The on-disk shape. Deliberately just a name and addresses — no ids or square
/// positions — so the file stays readable and hand-editable.
struct BookmarksFile: Codable {
    struct Entry: Codable {
        var name: String
        var url: String
        var notes: String?
    }

    var version: Int = 1
    var frame: String?
    /// Who made it. Kept so a frame handed on still says whose it was.
    var author: String?
    var sites: [Entry]
}

extension BrowserModel {
    // MARK: - Export

    /// e.g. elliott-cost-my-frame-made-on-2026-07-29.json — named for whoever
    /// made the frame rather than whoever happens to be exporting it, so
    /// someone else's frame passed on keeps their name on the file.
    private func filename(for frame: Frame) -> String {
        let user = (frame.displayAuthor ?? Self.thisUser)
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let parts = [user, frame.slug].filter { !$0.isEmpty }
        let stem = parts.isEmpty ? "frame" : parts.joined(separator: "-")
        return "\(stem)-made-on-\(formatter.string(from: Date())).json"
    }

    func exportFrame(_ frame: Frame) {
        guard !frame.sites.isEmpty else {
            alert = BrowserAlert(title: "Nothing to Export",
                                 message: "\(frame.displayName) has no sites in it yet.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Frame"
        panel.nameFieldStringValue = filename(for: frame)
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let file = BookmarksFile(
                frame: frame.name,
                author: frame.displayAuthor,
                sites: frame.sites.map { .init(name: $0.name, url: $0.url, notes: $0.notes) })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(file).write(to: url)
        } catch {
            alert = BrowserAlert(title: "Couldn't Export",
                                 message: error.localizedDescription)
        }
    }

    func exportCurrentFrame() {
        guard let frame = currentFrame else { return }
        exportFrame(frame)
    }

    // MARK: - Import

    /// Decodes a frame file. `fallbackName` is used when the file doesn't name
    /// itself — normally the filename it arrived as.
    func makeFrame(from data: Data, fallbackName: String) throws -> Frame {
        let decoder = JSONDecoder()
        let name: String
        let author: String?
        let entries: [BookmarksFile.Entry]

        if let file = try? decoder.decode(BookmarksFile.self, from: data) {
            name = file.frame?.isEmpty == false ? file.frame! : fallbackName
            author = file.author
            entries = file.sites
        } else {
            // Also accept a bare array, which is what people tend to hand-write.
            entries = try decoder.decode([BookmarksFile.Entry].self, from: data)
            name = fallbackName
            author = nil
        }

        let sites = entries.compactMap { entry -> Site? in
            let site = Site(name: entry.name, url: entry.url, notes: entry.notes)
            return site.identity == nil ? nil : site
        }
        return Frame(name: name, sites: sites, author: author)
    }

    /// Bring a frame in as a new frame and switch to it.
    func loadFrame(from data: Data, fallbackName: String) {
        do {
            let frame = try makeFrame(from: data, fallbackName: fallbackName)
            guard !frame.sites.isEmpty else {
                alert = BrowserAlert(title: "Empty Frame",
                                     message: "That file didn't contain any sites.")
                return
            }
            addFrame(named: frame.name, sites: frame.sites, author: frame.author)
            if let added = frames.last {
                select(added)
            }
        } catch {
            alert = BrowserAlert(title: "Couldn't Load Frame",
                                 message: "That file isn't frame JSON. \(error.localizedDescription)")
        }
    }

    func importBookmarks() {
        let panel = NSOpenPanel()
        panel.title = "Load Local Frame"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            loadFrame(from: try Data(contentsOf: url),
                      fallbackName: url.deletingPathExtension().lastPathComponent)
        } catch {
            alert = BrowserAlert(title: "Couldn't Load Frame",
                                 message: error.localizedDescription)
        }
    }

    /// Fetch someone else's exported frame straight off the web.
    func importBookmarksFromURL() {
        let field = NSTextField.addressField(placeholder: "https://example.com/frame.json")

        let prompt = NSAlert()
        prompt.messageText = "Load Frame from URL"
        prompt.informativeText = "Paste a link to an exported frame."
        prompt.addButton(withTitle: "Load")
        prompt.addButton(withTitle: "Cancel")
        prompt.accessoryView = field
        prompt.window.initialFirstResponder = field

        guard prompt.runModal() == .alertFirstButtonReturn,
              let url = URL.normalized(from: field.stringValue) else { return }

        Task { @MainActor in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                loadFrame(from: data,
                          fallbackName: url.deletingPathExtension().lastPathComponent)
            } catch {
                alert = BrowserAlert(title: "Couldn't Load Frame",
                                     message: "\(url.absoluteString)\n\n\(error.localizedDescription)")
            }
        }
    }
}

extension NSTextField {
    /// A box to paste an address into. Wide, single-line, and scrolling rather
    /// than truncating: a pasted URL that outruns the box should run off the
    /// end of it, not turn into an ellipsis that reads as though the address
    /// itself had been shortened.
    static func addressField(placeholder: String) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }
}

extension Site {
    /// What counts as "the same site" when de-duplicating. A trailing slash
    /// shouldn't make are.na and are.na/ two different bookmarks.
    var identity: String? {
        guard let text = resolvedURL?.absoluteString.lowercased() else { return nil }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}
