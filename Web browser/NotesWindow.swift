//
//  NotesWindow.swift
//  Web browser
//
//  A plain-text notepad for one site, in its own window. What you write is kept
//  with the site in its frame, and travels with an export. Which site it shows
//  follows whatever page is open, so it moves with you round the frame.
//

import SwiftUI

struct NotesWindow: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        Group {
            if let site = model.siteForNotes {
                TextEditor(text: Binding(
                    get: { model.notes(for: site.id) },
                    set: { model.setNotes($0, for: site.id) }
                ))
                // TextEdit's plain-text face, a size up for readability.
                .font(.custom("Menlo", size: 13))
                .lineSpacing(0)
                .foregroundStyle(.black)
                .scrollContentBackground(.hidden)
                .padding(.top, 8)
                .background(Color.notePaper)
            } else {
                // Nowhere to keep a note for a page the frame doesn't hold.
                Text(model.sites.isEmpty
                     ? "Add a site to this frame to write notes about it."
                     : "This page isn't in the frame, so there's nothing to write notes on. Open one of the frame's sites.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.placeholderText)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.frameBackground)
            }
        }
        .frame(minWidth: 260, minHeight: 220)
        .background(WindowTitle(text: title))
    }

    /// The site's address, shown in the title bar instead of above the text.
    private var title: String {
        guard let site = model.siteForNotes else { return "Notes" }
        return site.resolvedURL?.absoluteString ?? site.url
    }
}

/// Retitles whichever window this view lands in. The scene's own title is
/// fixed, so the address has to be pushed onto the NSWindow.
private struct WindowTitle: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.title = text }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.title = text }
    }
}
