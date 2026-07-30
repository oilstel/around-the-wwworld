//
//  AddEditSiteView.swift
//  Web browser
//
//  Created by Elliott Cost on 1/19/26.
//

import SwiftUI

struct AddEditSiteView: View {
    let model: BrowserModel
    let editing: Site?
    let slot: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var url: String
    @State private var name: String
    @State private var lookedUpURL = ""
    @FocusState private var urlFocused: Bool

    init(model: BrowserModel, editing: Site?, slot: Int?) {
        self.model = model
        self.editing = editing
        self.slot = slot
        _url = State(initialValue: editing?.url ?? "")
        _name = State(initialValue: editing?.name ?? "")
    }

    private var canSave: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "Add Site" : "Edit Site")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)

            Form {
                TextField("URL", text: $url, prompt: Text("example.com"))
                    .focused($urlFocused)
                    .onSubmit(save)

                TextField("Name", text: $name, prompt: Text("optional"))
            }
            .formStyle(.columns)
            // Fetching on focus-out rather than per keystroke, so a half-typed
            // domain doesn't get looked up.
            .onChange(of: urlFocused) { _, focused in
                if !focused { Task { await fillNameFromTitle() } }
            }

            HStack {
                if let site = editing {
                    Button("Remove", role: .destructive) {
                        model.delete(site)
                        dismiss()
                    }
                }

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color.frameBackground)
    }

    /// Look up the page's <title> and use it, unless a name was typed already.
    private func fillNameFromTitle() async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lookedUpURL,
              name.isEmpty, let pageURL = URL.normalized(from: trimmed) else { return }

        lookedUpURL = trimmed
        if let title = await PageTitleFetcher.title(of: pageURL), name.isEmpty {
            name = title
        }
    }

    private func save() {
        guard canSave else { return }

        Task {
            // Catch the case where Save is hit without ever leaving the URL field.
            await fillNameFromTitle()

            let site = Site(id: editing?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                            slot: editing?.slot ?? slot)

            if editing == nil {
                model.add(site, inSlot: slot)
            } else {
                model.update(site)
            }
            dismiss()
        }
    }
}
