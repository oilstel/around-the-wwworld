//
//  Web_browserApp.swift
//  Web browser
//
//  Created by Elliott Cost on 1/19/26.
//

import SwiftUI

let NotesWindowID = "notes"

@main
struct Web_browserApp: App {
    @StateObject private var model = BrowserModel()

    init() {
        // Frames aren't tabs. Turning tabbing off is what takes "Show Tab Bar"
        // and "Show All Tabs" out of the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        // A single Window rather than a WindowGroup: every frame lives in this
        // one window, so there's no New Window item to remove.
        Window("Around the wwworld", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 900, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            BrowserCommands(model: model)
        }

        Window("Notes", id: NotesWindowID) {
            NotesWindow(model: model)
        }
        .defaultSize(width: 360, height: 420)
    }
}

struct BrowserCommands: Commands {
    @ObservedObject var model: BrowserModel

    var body: some Commands {
        // Takes the slot the standard "About" item occupies, at the top of the
        // app menu.
        CommandGroup(replacing: .appInfo) {
            Button("About") { model.showsAbout = true }
        }

        // Shown as a sheet on the one window rather than in a Settings scene,
        // which would open a second window this app otherwise never has.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.showsSettings = true }
                .keyboardShortcut(",")
        }

        CommandGroup(replacing: .newItem) {
            Button("New Frame") { model.newFrame() }
                .keyboardShortcut("n")

            Button("Add Site…") { model.sheet = .add(nil) }
                .keyboardShortcut("d")

            // Act on whatever's highlighted in the frames grid.
            Button("Open Frame") { model.openSelectedFrame() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.mode != .frames || model.selectedFrame == nil)

            Button("Delete Frame…") { model.requestRemovalOfSelectedFrame() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.mode != .frames || model.selectedFrame == nil)

            Divider()
            Button("Load Local Frame…") { model.importBookmarks() }
            Button("Load Frame from URL…") { model.importBookmarksFromURL() }
            Button("Load Are.na Channel as Frame…") { model.importArenaChannel() }
            Button("Export Frame…") { model.exportCurrentFrame() }

            Divider()
            Button("Open in Default Browser") { model.openInDefaultBrowser() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model.selectedSite == nil)
        }

        CommandMenu("Site") {
            Button(model.isTouring ? "Stop Going Around the World" : "Around the World") {
                model.toggleTour()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(model.sites.isEmpty)

            Divider()

            Button("Previous Site") { model.selectPreviousSite() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(model.sites.isEmpty)

            Button("Next Site") { model.selectNextSite() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(model.sites.isEmpty)

            Divider()

            Button("Back") { model.engine.goBack() }
                .keyboardShortcut("[")
                .disabled(!model.engine.canGoBack)

            Button("Forward") { model.engine.goForward() }
                .keyboardShortcut("]")
                .disabled(!model.engine.canGoForward)

            Button("Reload") { model.engine.reload() }
                .keyboardShortcut("r")
                .disabled(model.selectedSite == nil)

            Divider()

            Button("Edit Site…") {
                if let site = model.selectedSite { model.sheet = .edit(site) }
            }
            .disabled(model.selectedSite == nil)

            Button("Remove Site…") {
                if let site = model.selectedSite { model.requestRemoval(of: site) }
            }
            .disabled(model.selectedSite == nil)

            Divider()

            Button("Refresh Favicons") { FaviconLoader.shared.refreshAll() }
        }

        CommandGroup(after: .toolbar) {
            Button("All Frames") { model.mode = model.mode == .frames ? .browser : .frames }
                .keyboardShortcut("1", modifiers: .command)

            Button("Sites in This Frame") { model.mode = model.mode == .directory ? .browser : .directory }
                .keyboardShortcut("2", modifiers: .command)

            Divider()

            Toggle("Dense Frame", isOn: $model.isDense)
        }
    }
}
