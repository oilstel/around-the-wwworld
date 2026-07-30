//
//  SiteListView.swift
//  Web browser
//
//  The table of every site you've added: favicon, editable name and address,
//  and drag-to-reorder.
//
//  Deliberately not a List: a List with .onMove turns every row into a drag
//  source, and the drag swallows the click before a text field can take it, so
//  nothing is editable. Reordering hangs off an explicit grip instead.
//

import SwiftUI
import UniformTypeIdentifiers

struct SiteListView: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            if model.sites.isEmpty {
                Spacer()
                // The ring isn't on screen in this view, so pointing at its
                // squares would be no help.
                Text("No sites in this frame yet. Add one with ⌘D.")
                    .font(.system(size: 13))
                    .foregroundColor(.placeholderText)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.orderedSites.enumerated()), id: \.element.id) { index, site in
                            SiteRow(site: site, index: index, model: model)
                            Rectangle()
                                .fill(Color.separator.opacity(0.5))
                                .frame(height: 1)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

private struct SiteRow: View {
    let site: Site
    let index: Int
    let model: BrowserModel

    @Environment(\.openWindow) private var openWindow
    @State private var name: String
    @State private var url: String

    init(site: Site, index: Int, model: BrowserModel) {
        self.site = site
        self.index = index
        self.model = model
        // Filled with the host when unnamed, so every row shows real editable
        // text rather than a grey placeholder.
        _name = State(initialValue: site.displayName)
        _url = State(initialValue: site.url)
    }

    var body: some View {
        HStack(spacing: 10) {
            // The only draggable part of the row, so the fields keep their clicks.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.35))
                .frame(width: 16, height: 20)
                .contentShape(Rectangle())
                .help("Drag to reorder")
                .siteDragSource(site)

            Button {
                model.open(site)
                model.mode = .browser
            } label: {
                FaviconSquareView(site: site, size: 22, highlighted: false)
            }
            .buttonStyle(.plain)
            .help("Open \(site.displayName)")

            field($name, placeholder: site.host, font: .systemFont(ofSize: 13))
            field($url, placeholder: "example.com", font: .systemFont(ofSize: 13))

            Button {
                model.requestRemoval(of: site)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.placeholderText)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onDrop(of: [.text], delegate: SiteMoveDropDelegate(index: index, model: model))
        .contextMenu {
            Button("Open") {
                model.open(site)
                model.mode = .browser
            }
            Button("Open in Default Browser") {
                if let url = site.resolvedURL { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Show Notes") {
                model.open(site)
                model.mode = .browser
                openWindow(id: NotesWindowID)
            }
            Button("New Letter Colour") { model.randomizeColor(of: site) }
            Button("Remove…", role: .destructive) { model.requestRemoval(of: site) }
        }
    }

    private func field(_ text: Binding<String>, placeholder: String, font: NSFont) -> some View {
        EditableTextField(text: text,
                          placeholder: placeholder,
                          font: font,
                          onSubmit: commit,
                          onEditingChanged: { editing in
                              // Commit when the field loses focus, so clicking
                              // away doesn't discard the edit.
                              if !editing { commit() }
                          })
            .frame(height: 17)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Rectangle().fill(Color.urlBarBackground))
    }

    private func commit() {
        var updated = site
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard updated != site, !updated.url.isEmpty else { return }
        model.update(updated)
    }
}
