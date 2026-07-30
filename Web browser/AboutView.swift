//
//  AboutView.swift
//  Web browser
//
//  What this thing is for. Its links open in the frame rather than handing you
//  off to another browser.
//

import SwiftUI

struct AboutView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    /// Read from the bundle, so it follows the project's version rather than
    /// being typed in here and going stale.
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Around the wwworld (v\(version))")
                .font(.system(size: 13))
                .foregroundStyle(.black)

            VStack(alignment: .leading, spacing: 12) {
                Text("For making frames of your friends' websites.")
                Text(basedOn)
                Text(byline)
            }
            .font(.system(size: 13))
            .foregroundStyle(.black)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(Color.frameBackground)
        // Catch the links rather than letting them leave for Safari.
        .environment(\.openURL, OpenURLAction { url in
            model.visit(url)
            dismiss()
            return .handled
        })
    }

    // Built up by hand rather than from markdown, which would swallow the
    // literal <iframe> as an HTML tag.
    private var basedOn: AttributedString {
        var text = AttributedString("This software is based on a past <iframe> frame website by ")
        text += link("Laurel Schwulst", to: "https://laurelschwulst.com/")
        text += AttributedString(".")
        return text
    }

    private var byline: AttributedString {
        var text = AttributedString("Made on ")
        text += link("Elliott's Computer", to: "https://elliott.computer/")
        text += AttributedString(". A software by ")
        text += link("Bell Kiosk", to: "https://bellkiosk.website/")
        text += AttributedString(", 2026.")
        return text
    }

    private func link(_ label: String, to address: String) -> AttributedString {
        var run = AttributedString(label)
        run.link = URL(string: address)
        run.foregroundColor = .selectionBorder
        run.underlineStyle = .single
        return run
    }
}
