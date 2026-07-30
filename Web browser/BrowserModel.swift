//
//  BrowserModel.swift
//  Web browser
//
//  Every frame you've got, which one is open, and the state of browsing it.
//

import Combine
import Foundation
import SwiftUI

/// What to do with a frame holding more sites than the ring has squares.
enum SquareOverflow: String, CaseIterable, Identifiable {
    /// A page number in the top-left corner, squares kept at full size.
    case paginate
    /// One ring, squares shrinking to make room.
    case shrink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paginate: "Turn the pages"
        case .shrink: "Shrink the squares"
        }
    }

    var detail: String {
        switch self {
        case .paginate: "A number in the top-left corner turns from one page of favicons to the next."
        case .shrink: "Every site stays on the ring at once, the squares getting smaller the more you keep."
        }
    }
}

/// What fills the middle of the window.
enum ViewMode {
    case browser
    case directory   // the sites in this frame, as a list
    case frames      // every frame, as a grid
}

/// What the add/edit sheet is showing, if anything.
enum SiteSheet: Identifiable {
    /// Carries the square that was clicked, so the new site lands there.
    case add(Int?)
    case edit(Site)

    var id: String {
        switch self {
        case .add(let slot): "add-\(slot.map(String.init) ?? "auto")"
        case .edit(let site): site.id.uuidString
        }
    }
}

struct BrowserAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published private(set) var frames: [Frame] = []
    @Published private(set) var currentFrameID: Frame.ID?

    @Published var mode: ViewMode = .browser
    @Published var selectedID: Site.ID?
    @Published var sheet: SiteSheet?
    @Published var alert: BrowserAlert?
    @Published var showsAbout = false
    @Published var showsSettings = false
    @Published var sitePendingRemoval: Site?
    @Published var framePendingRemoval: Frame?
    @Published var renamingFrame: Frame?
    /// Highlighted in the grid by a single click. Separate from the frame
    /// that's actually open, which takes a double click.
    @Published var selectedFrameID: Frame.ID?
    /// Which page of favicons the ring is showing. Only ever past zero when a
    /// frame holds more sites than the window has squares; the ring's geometry
    /// decides how many fit, so the clamping lives with the layout.
    @Published var framePage = 0
    @Published private(set) var isTouring = false
    @Published private var isViewportBlank = false
    /// Squares packed edge to edge, with no margin left round the window.
    @Published var isDense: Bool {
        didSet { UserDefaults.standard.set(isDense, forKey: Self.denseKey) }
    }
    @Published var overflow: SquareOverflow {
        didSet { UserDefaults.standard.set(overflow.rawValue, forKey: Self.overflowKey) }
    }

    let engine = WebEngine()

    private var tour: Task<Void, Never>?
    private static let framesKey = "saved_frames"
    private static let currentFrameKey = "current_frame"
    private static let legacySitesKey = "saved_sites"
    private static let denseKey = "dense_ring"
    private static let overflowKey = "square_overflow"
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Dense unless it's been turned off — .bool would read a missing key as
        // false, which is the opposite of the default wanted here.
        isDense = UserDefaults.standard.object(forKey: Self.denseKey) as? Bool ?? true

        let storedOverflow = UserDefaults.standard.string(forKey: Self.overflowKey)
        overflow = storedOverflow.flatMap(SquareOverflow.init(rawValue:)) ?? .paginate

        load()

        // Somewhere different each launch, rather than always the first square.
        if let site = sites.randomElement() {
            open(site)
        }

        // Menu items key off the engine's back/forward state, so republish it.
        engine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Keep the ring's outline on whichever site is actually loaded, no
        // matter what moved us — a click, a link, or a shortcut WebKit took
        // for itself before the menu saw it.
        engine.onNavigate = { [weak self] url in
            self?.syncSelection(to: url)
        }
    }

    private func syncSelection(to url: URL) {
        guard let host = url.host() else { return }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        // If what's selected already serves this host, leave it be. Picking the
        // first match instead would drag the selection back to the earlier copy
        // whenever a frame holds the same host twice — which makes stepping
        // through the ring loop over a handful of sites.
        if let selected = selectedSite, selected.host == bare { return }

        if let match = sites.first(where: { $0.host == bare }) {
            selectedID = match.id
            isViewportBlank = false
        }
    }

    // MARK: - Loading and saving

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.framesKey),
           let decoded = try? JSONDecoder().decode([Frame].self, from: data), !decoded.isEmpty {
            frames = decoded
        } else if let legacy = UserDefaults.standard.data(forKey: Self.legacySitesKey),
                  let sites = try? JSONDecoder().decode([Site].self, from: legacy), !sites.isEmpty {
            // Everything saved before frames existed becomes the first one.
            frames = [Frame(name: "My frame",
                            sites: sites.sorted { ($0.slot ?? .max) < ($1.slot ?? .max) })]
        } else {
            frames = [Frame(name: "My frame")]
        }

        let remembered = UserDefaults.standard.string(forKey: Self.currentFrameKey).flatMap(UUID.init(uuidString:))
        currentFrameID = frames.contains { $0.id == remembered } ? remembered : frames.first?.id
        selectedFrameID = currentFrameID
        save()
    }

    private func save() {
        // Position is just the index; keep the stored slot in step so ordering
        // survives a relaunch.
        if let index = currentFrameIndex {
            for site in frames[index].sites.indices where frames[index].sites[site].slot != site {
                frames[index].sites[site].slot = site
            }
        }

        if let encoded = try? JSONEncoder().encode(frames) {
            UserDefaults.standard.set(encoded, forKey: Self.framesKey)
        }
        UserDefaults.standard.set(currentFrameID?.uuidString, forKey: Self.currentFrameKey)
    }

    // MARK: - Frames

    private var currentFrameIndex: Int? {
        frames.firstIndex { $0.id == currentFrameID }
    }

    var currentFrame: Frame? {
        currentFrameIndex.map { frames[$0] }
    }

    var frameName: String {
        currentFrame?.displayName ?? "Untitled frame"
    }

    private func mutateCurrentFrame(_ change: (inout Frame) -> Void) {
        guard let index = currentFrameIndex else { return }
        change(&frames[index])
        save()
    }

    func select(_ frame: Frame) {
        stopTour()
        currentFrameID = frame.id
        selectedID = nil
        framePage = 0
        mode = .browser
        save()

        if let site = frame.sites.randomElement() {
            open(site)
        } else {
            // An empty frame shows its invitation, not the last frame's page.
            isViewportBlank = true
            engine.clear()
        }
    }

    /// Make an empty frame, switch to it and offer to name it. It starts
    /// nameless so the rename sheet opens on an empty field rather than making
    /// you clear a placeholder out first.
    func newFrame() {
        let frame = addFrame(named: "")
        select(frame)
        renamingFrame = frame
    }

    @discardableResult
    func addFrame(named name: String, sites: [Site] = []) -> Frame {
        let frame = Frame(name: name, sites: sites)
        frames.append(frame)
        save()
        return frame
    }

    /// Drag one frame tile onto another to reorder the grid.
    func moveFrame(id: Frame.ID, to index: Int) {
        guard let from = frames.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(index, 0), frames.count - 1)
        guard from != to else { return }

        let frame = frames.remove(at: from)
        frames.insert(frame, at: to)
        save()
    }

    func rename(_ frame: Frame, to name: String) {
        guard let index = frames.firstIndex(where: { $0.id == frame.id }) else { return }
        frames[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    var selectedFrame: Frame? {
        frames.first { $0.id == selectedFrameID }
    }

    /// Open whichever frame is highlighted in the grid.
    func openSelectedFrame() {
        guard let frame = selectedFrame else { return }
        select(frame)
    }

    func requestRemovalOfSelectedFrame() {
        guard let frame = selectedFrame else { return }
        requestRemoval(of: frame)
    }

    func requestRemoval(of frame: Frame) {
        framePendingRemoval = frame
    }

    func confirmFrameRemoval() {
        defer { framePendingRemoval = nil }
        guard let frame = framePendingRemoval,
              let index = frames.firstIndex(where: { $0.id == frame.id }) else { return }

        frames.remove(at: index)
        if frames.isEmpty {
            frames = [Frame(name: "My frame")]
        }
        if currentFrameID == frame.id, let next = frames.first {
            select(next)
        }
        save()
    }

    // MARK: - Sites in the current frame

    var sites: [Site] { currentFrame?.sites ?? [] }
    var orderedSites: [Site] { sites }

    /// Which site sits in which square. Sites pack from the first square with
    /// no gaps, so a site's position is just its index.
    var slotMap: [Int: Site] {
        Dictionary(uniqueKeysWithValues: sites.enumerated().map { ($0.offset, $0.element) })
    }

    /// The next square a new site would land in.
    var nextFreeSlot: Int { sites.count }

    var selectedSite: Site? {
        sites.first { $0.id == selectedID }
    }

    // MARK: - Navigation

    func open(_ site: Site) {
        selectedID = site.id
        isViewportBlank = false
        if let url = site.resolvedURL {
            engine.load(url)
        }
    }

    /// What the window title shows.
    var displayURL: String {
        engine.currentURL?.absoluteString
            ?? selectedSite?.resolvedURL?.absoluteString
            ?? ""
    }

    /// True once anything has been loaded. The web view keeps its last page
    /// after being cleared, so the blank flag has the final say.
    var hasContent: Bool {
        !isViewportBlank && (engine.currentURL != nil || selectedSite != nil)
    }

    /// Load an address in the current frame's viewport rather than handing it
    /// to the default browser.
    func visit(_ url: URL) {
        stopTour()
        mode = .browser
        isViewportBlank = false
        selectedID = sites.first { $0.resolvedURL?.host() == url.host() }?.id
        engine.load(url)
    }

    /// Somewhere else in this frame, picked at random. Deliberately never lands
    /// on the site already open — a shuffle that sometimes does nothing reads
    /// as a broken button.
    func openRandomSite() {
        stopTour()
        mode = .browser

        let elsewhere = sites.filter { $0.id != selectedID }
        if let site = (elsewhere.isEmpty ? sites : elsewhere).randomElement() {
            open(site)
        }
    }

    func openInDefaultBrowser() {
        guard let url = engine.currentURL ?? selectedSite?.resolvedURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Around the world

    /// Walks the ring one site at a time, a couple of seconds each, wrapping
    /// forever.
    func toggleTour() {
        isTouring ? stopTour() : startTour()
    }

    func startTour() {
        guard !sites.isEmpty, !isTouring else { return }
        isTouring = true

        tour = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.selectNextSite()
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.isTouring, !self.sites.isEmpty else { break }
            }
        }
    }

    func stopTour() {
        isTouring = false
        tour?.cancel()
        tour = nil
    }

    /// Step to the neighbouring favicon on the ring, wrapping around the ends.
    func selectPreviousSite() { step(by: -1) }
    func selectNextSite() { step(by: 1) }

    private func step(by delta: Int) {
        guard !sites.isEmpty else { return }

        guard let current = sites.firstIndex(where: { $0.id == selectedID }) else {
            open(sites[delta > 0 ? 0 : sites.count - 1])
            return
        }

        let next = (current + delta + sites.count) % sites.count
        open(sites[next])
    }

    // MARK: - Editing sites

    /// The site being viewed isn't in the frame, so it can be added.
    var canPlaceCurrentSite: Bool {
        selectedID == nil && !isViewportBlank && engine.currentURL != nil
    }

    /// Add whatever's on screen to the frame, in the next free square.
    func placeCurrentSite() {
        guard let url = engine.currentURL else { return }
        let site = Site(name: "", url: url.absoluteString)
        mutateCurrentFrame { $0.sites.append(site) }
        selectedID = site.id
    }

    func add(_ site: Site, inSlot slot: Int? = nil) {
        mutateCurrentFrame { frame in
            if let slot, slot < frame.sites.count {
                frame.sites.insert(site, at: slot)
            } else {
                frame.sites.append(site)
            }
        }
        open(site)
    }

    func update(_ site: Site) {
        guard let index = sites.firstIndex(where: { $0.id == site.id }) else { return }

        let previous = sites[index]
        var site = site
        site.slot = site.slot ?? previous.slot   // editing must not move the square
        mutateCurrentFrame { $0.sites[index] = site }

        if previous.host != site.host {
            FaviconLoader.shared.forget(previous)
        }
        // Only reload if the address actually changed; renaming shouldn't kick
        // the page you're reading.
        if selectedID == site.id, previous.url != site.url {
            open(site)
        }
    }

    /// The frame's site whose page is on screen. Notes hang off this, so they
    /// follow you round the frame — and go away if you wander onto something
    /// the frame doesn't contain, which has nowhere to keep a note.
    var siteForNotes: Site? {
        guard !isViewportBlank else { return nil }
        guard let current = engine.currentURL, let host = current.host() else { return selectedSite }

        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return sites.first { $0.host == bare }
    }

    func setNotes(_ text: String, for id: Site.ID) {
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateCurrentFrame { $0.sites[index].notes = trimmed.isEmpty ? nil : text }
    }

    func notes(for id: Site.ID) -> String {
        sites.first { $0.id == id }?.notes ?? ""
    }

    /// Re-roll the colour behind a site's letter square.
    func randomizeColor(of site: Site) {
        guard let index = sites.firstIndex(where: { $0.id == site.id }) else { return }
        mutateCurrentFrame { $0.sites[index].colorSeed = UInt64.random(in: 0...UInt64.max) }
    }

    /// Drop a favicon onto another square to rearrange the ring. The squares
    /// stay packed, so dropping past the end just moves it last.
    func move(id: Site.ID, toSlot slot: Int) {
        guard let from = sites.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(slot, 0), sites.count - 1)
        guard from != to else { return }

        mutateCurrentFrame { frame in
            let site = frame.sites.remove(at: from)
            frame.sites.insert(site, at: to)
        }
    }

    func reorder(from source: IndexSet, to destination: Int) {
        mutateCurrentFrame { $0.sites.move(fromOffsets: source, toOffset: destination) }
    }

    /// Append imported sites in file order, skipping any already here.
    func appendUnique(_ incoming: [Site]) -> (added: Int, skipped: Int) {
        var known = Set(sites.compactMap(\.identity))
        var added = 0
        var skipped = 0

        for site in incoming {
            guard let identity = site.identity else { continue }
            guard !known.contains(identity) else {
                skipped += 1
                continue
            }
            mutateCurrentFrame { $0.sites.append(site) }
            known.insert(identity)
            added += 1
        }
        return (added, skipped)
    }

    /// Removing is easy to do by accident and can't be undone, so it goes
    /// through a confirmation rather than straight to delete.
    func requestRemoval(of site: Site) {
        sitePendingRemoval = site
    }

    func confirmRemoval() {
        if let site = sitePendingRemoval {
            delete(site)
        }
        sitePendingRemoval = nil
    }

    func delete(_ site: Site) {
        mutateCurrentFrame { $0.sites.removeAll { $0.id == site.id } }
        FaviconLoader.shared.forget(site)

        if selectedID == site.id {
            selectedID = nil
            if let next = sites.first { open(next) }
        }
    }
}
