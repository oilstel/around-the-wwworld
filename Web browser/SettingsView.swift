//
//  SettingsView.swift
//  Web browser
//
//  How big the squares along the edge are, and what becomes of them when a
//  frame holds more sites than the ring has room for.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)

            section("The frame") {
                Toggle("Dense", isOn: $model.isDense)
                    .font(.system(size: 13))

                Text("Squares packed shoulder to shoulder, running right out to the edge of the window.")
                    .font(.system(size: 11))
                    .foregroundColor(.placeholderText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("More sites than squares") {
                Picker("", selection: $model.overflow) {
                    ForEach(SquareOverflow.allCases) { overflow in
                        Text(overflow.label).tag(overflow)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(model.overflow.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.placeholderText)
                    .fixedSize(horizontal: false, vertical: true)
                    // Both explanations run to two lines at this width; the
                    // fixed height keeps the panel from jumping between them.
                    .frame(height: 28, alignment: .topLeading)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Color.frameBackground)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)
            content()
        }
    }
}
