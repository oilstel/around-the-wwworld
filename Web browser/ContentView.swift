//
//  ContentView.swift
//  Web browser
//
//  Created by Elliott Cost on 1/19/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: BrowserModel
    @Environment(\.openWindow) private var openWindow

    /// The size squares are drawn at before anything shrinks them.
    private var square: CGFloat { model.squareSize.points }

    private let outerPadding: CGFloat = 10
    /// Tighter at the top, so the ring sits close under the title bar.
    private let topPadding: CGFloat = 3
    private let minGap: CGFloat = 9

    var body: some View {
        Group {
            switch model.mode {
            case .browser:
                browserFrame
            case .directory:
                // Fills the window on its own: no ring, no viewport box.
                SiteListView(model: model)
            case .frames:
                FramesGridView(model: model)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color.frameBackground)
        .background(WindowStyler(title: windowTitle))
        // Drop someone's exported frame anywhere on the window to load it.
        .onDrop(of: [.fileURL], delegate: FrameFileDropDelegate(model: model))
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Text(model.frameName)
                    .font(.system(size: 13))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    // SwiftUI's .contextMenu doesn't fire inside a toolbar
                    // item, so the right-click is handled in AppKit.
                    .overlay {
                        RightClickMenu(items: [
                            ("Rename Frame…", {
                                if let frame = model.currentFrame { model.renamingFrame = frame }
                            }),
                            ("Export Frame…", {
                                if let frame = model.currentFrame { model.exportFrame(frame) }
                            })
                        ])
                    }
                    .help("Right-click to rename this frame")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Sonoma lays this group out straight after the centred items
                // rather than pinning it to the trailing edge; the spacer
                // pushes it right on every version.
                Spacer()

                // Hidden rather than removed away from the browser: dropping
                // them would slide the list button across the bar.
                Group {
                    arrow("chevron.left", label: "Back", enabled: model.engine.canGoBack) {
                        model.engine.goBack()
                    }
                    arrow("chevron.right", label: "Forward", enabled: model.engine.canGoForward) {
                        model.engine.goForward()
                    }
                }
                .opacity(model.mode == .browser ? 1 : 0)
                .allowsHitTesting(model.mode == .browser)

                Button {
                    model.openRandomSite()
                } label: {
                    // The glyph is a thin stroked line, which on its own only
                    // answers to clicks that land on the line itself. The clear
                    // square behind it takes the whole area, the way the tour
                    // button does.
                    ZStack {
                        Color.clear

                        SpiralGlyph()
                            .stroke(Color.black.opacity(model.sites.isEmpty ? 0.45 : 1),
                                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                            .frame(width: 16, height: 16)
                    }
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("A site at random")
                .disabled(model.sites.isEmpty)
                // Nothing to pick from while you're looking at every frame.
                // Hidden rather than removed so the bar doesn't reflow.
                .opacity(model.mode == .frames ? 0 : 1)
                .allowsHitTesting(model.mode != .frames)

                Button {
                    model.mode = model.mode == .directory ? .browser : .directory
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.mode == .directory ? Color.selectionBorder : .black)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.mode == .directory ? "Back to the page" : "Sites in this frame")
                // Nothing to list while you're looking at every frame. Hidden
                // rather than removed so the bar doesn't reflow.
                .opacity(model.mode == .frames ? 0 : 1)
                .allowsHitTesting(model.mode != .frames)

                Button {
                    model.mode = model.mode == .frames ? .browser : .frames
                } label: {
                    FrameGlyph()
                        .fill(model.mode == .frames ? Color.selectionBorder : .black,
                              style: FillStyle(eoFill: true))
                        .frame(width: 17, height: 17)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.mode == .frames ? "Back to the frame" : "All frames")
            }
        }
        .modifier(HideToolbarTitle())
        .toolbarBackground(Color.frameBackground, for: .windowToolbar)
        .alert(model.alert?.title ?? "", isPresented: Binding(
            get: { model.alert != nil },
            set: { if !$0 { model.alert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
        }
        .confirmationDialog(
            "Remove \(model.sitePendingRemoval?.displayName ?? "this site")?",
            isPresented: Binding(
                get: { model.sitePendingRemoval != nil },
                set: { if !$0 { model.sitePendingRemoval = nil } }
            ),
            presenting: model.sitePendingRemoval
        ) { _ in
            Button("Remove", role: .destructive) { model.confirmRemoval() }
            Button("Cancel", role: .cancel) { model.sitePendingRemoval = nil }
        } message: { site in
            Text("\(site.url)\n\nThis can't be undone.")
        }
        .confirmationDialog(
            "Delete \(model.framePendingRemoval?.displayName ?? "this frame")?",
            isPresented: Binding(
                get: { model.framePendingRemoval != nil },
                set: { if !$0 { model.framePendingRemoval = nil } }
            ),
            presenting: model.framePendingRemoval
        ) { _ in
            Button("Delete", role: .destructive) { model.confirmFrameRemoval() }
            Button("Cancel", role: .cancel) { model.framePendingRemoval = nil }
        } message: { frame in
            Text("\(frame.sites.count) site\(frame.sites.count == 1 ? "" : "s") will go with it. Export it first if you want to keep it.")
        }
        .sheet(isPresented: $model.showsAbout) {
            AboutView(model: model).lightSheet()
        }
        .sheet(isPresented: $model.showsSettings) {
            SettingsView(model: model).lightSheet()
        }
        .sheet(item: $model.renamingFrame) { frame in
            RenameFrameView(model: model, frame: frame).lightSheet()
        }
        .sheet(item: $model.sheet) { sheet in
            Group {
                switch sheet {
                case .add(let slot):
                    AddEditSiteView(model: model, editing: nil, slot: slot)
                case .edit(let site):
                    AddEditSiteView(model: model, editing: site, slot: site.slot)
                }
            }
            .lightSheet()
        }
    }

    /// The ring of favicon squares around the viewport.
    private var browserFrame: some View {
        GeometryReader { geometry in
            // A first pass at the usual margin, only to find out how big the
            // squares come out — shrunk squares need the border brought in with
            // them, or a frame full of little squares sits inside a wide band of
            // nothing. Dense gives the margin up altogether.
            let full = CGSize(width: geometry.size.width - 2 * outerPadding,
                              height: geometry.size.height - outerPadding - topPadding)
            let scale = ring(in: full).square / square

            let margin = model.isDense ? 0 : max(2, (outerPadding * scale).rounded())
            // Dense leaves a hairline's worth of room under the toolbar, for the
            // rule that keeps the squares from running straight into it.
            let top = model.isDense ? 1 : max(1, (topPadding * scale).rounded())

            let content = CGSize(width: geometry.size.width - 2 * margin,
                                 height: geometry.size.height - margin - top)
            let layout = ring(in: content)
            let paging = RingPaging(siteCount: model.sites.count,
                                    slots: layout.slotCount,
                                    page: model.framePage)

            ZStack(alignment: .topLeading) {
                // Establishes the stack's size. Without it the stack shrinks to
                // fit its children (slots are positioned with .offset, which
                // doesn't count toward layout) and the ring drifts off-centre.
                Color.frameBackground
                    .frame(width: content.width, height: content.height)

                let placed = model.slotMap
                // The top-right corner is the tour button and never holds a
                // site, so everything after it shifts back one position.
                let playIndex = layout.columns - 1

                ForEach(0..<layout.slotCount, id: \.self) { index in
                    if index == playIndex {
                        tourButton(at: index, in: layout)
                    } else if paging.isPaginated && index == 0 {
                        pageButton(at: index, in: layout, paging: paging)
                    } else {
                        let onPage = ringPosition(of: index,
                                                  playIndex: playIndex,
                                                  paginated: paging.isPaginated)
                        let position = paging.frameIndex(of: onPage)
                        slot(at: index, position: position, in: layout, site: placed[position])
                    }
                }
                viewport(in: layout)
                noteBadge(in: layout)
            }
            // Widening the window, or emptying the frame out, can leave the
            // remembered page past the end. It's clamped for drawing either
            // way; this keeps the model from holding onto the stale number.
            .onChange(of: paging.pageCount) { _, count in
                model.framePage = min(model.framePage, count - 1)
            }
            // Stepping round the ring — by keyboard, or on the tour — can land
            // on a site the current page doesn't show, so the page follows it.
            .onChange(of: model.selectedID) { _, id in
                guard paging.isPaginated,
                      let index = model.sites.firstIndex(where: { $0.id == id }) else { return }
                model.framePage = paging.pageIndex(of: index)
            }
            .frame(width: content.width, height: content.height, alignment: .topLeading)
            .padding(.top, top)
            .padding(.horizontal, margin)
            .padding(.bottom, margin)
            // Without a margin there's nothing between the top row of squares
            // and the toolbar, so a rule stands in for the gap.
            .overlay(alignment: .top) {
                if model.isDense {
                    Rectangle()
                        .fill(Color.separator)
                        .frame(height: 1)
                }
            }
        }
    }

    /// The ring for a given content size. Shrunk to hold every site at once if
    /// that's the setting — pagination is worked out either way, and simply
    /// comes out at a single page whenever the sites do fit. Dense asks for no
    /// gaps at all, which only lands exact if the square happens to divide the
    /// window, so there the size gives a little instead.
    private func ring(in content: CGSize) -> RingLayout {
        let gap = model.isDense ? 0 : minGap
        let side = model.isDense ? RingLayout.evenSquare(near: square, in: content) : square

        return model.overflow == .shrink
            ? RingLayout.fitting(siteCount: model.sites.count, in: content,
                                 preferred: side, minGap: gap)
            : RingLayout(size: content, square: side, minGap: gap)
    }

    /// A bare glyph, no button chrome behind it. Deliberately not .disabled():
    /// the system's dimming stacks on top of the opacity below and washes the
    /// arrows out, so the unavailable state is drawn by hand instead.
    private func arrow(_ symbol: String, label: String, enabled: Bool,
                       action: @escaping () -> Void) -> some View {
        Button {
            if enabled { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(enabled ? 1 : 0.45))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    /// Not drawn in the title bar (the toolbar shows the frame name) but kept
    /// current for the Window menu.
    private var windowTitle: String {
        model.frameName
    }

    // MARK: - Ring

    /// Fixed in the top-right corner: starts and stops the tour, and can't be
    /// dragged or replaced by a site.
    private func tourButton(at index: Int, in layout: RingLayout) -> some View {
        let frame = layout.rect(at: index)

        return Button {
            model.toggleTour()
        } label: {
            ZStack {
                // Nothing behind it — the glyph sits straight on the frame.
                Color.clear

                if model.isTouring {
                    PauseGlyph()
                        .fill(Color.tourButton)
                        .frame(width: layout.square * 0.58, height: layout.square * 0.66)
                } else {
                    PlayGlyph()
                        .fill(Color.tourButton)
                        .frame(width: layout.square * 0.62, height: layout.square * 0.68)
                }
            }
            .frame(width: layout.square, height: layout.square)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.isTouring ? "Stop going around the world" : "Around the world")
        .disabled(model.sites.isEmpty)
        .offset(x: frame.minX, y: frame.minY)
    }

    /// Fixed in the top-left corner once a frame outgrows the ring: the page
    /// you're on, and a click turns to the next one, wrapping round to the
    /// first. Built like a site's letter square — same bevel, same face — so it
    /// sits in the ring rather than on it.
    private func pageButton(at index: Int, in layout: RingLayout, paging: RingPaging) -> some View {
        let frame = layout.rect(at: index)

        return Button {
            model.stopTour()   // a deliberate turn of the page ends the tour
            model.framePage = (paging.page + 1) % paging.pageCount
        } label: {
            Rectangle()
                .fill(Color.tourButton)
                .overlay {
                    InnerBevel()
                        .fill(Color.black.opacity(0.2))
                }
                .overlay {
                    Text("\(paging.page + 1)")
                        .font(.custom("Times New Roman", size: layout.square * 0.52))
                        .foregroundColor(.white)
                }
                .frame(width: layout.square, height: layout.square)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Page \(paging.page + 1) of \(paging.pageCount) — click for the next")
        .onHover { inside in
            // .pointerStyle is macOS 15+, so the cursor is set by hand, the way
            // the favicon squares do it.
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .offset(x: frame.minX, y: frame.minY)
    }

    /// Where a slot sits among the squares that actually hold sites. The tour
    /// button and, on a paginated frame, the page number are skipped, so every
    /// square after them shifts back.
    private func ringPosition(of index: Int, playIndex: Int, paginated: Bool) -> Int {
        var position = index
        if index > playIndex { position -= 1 }
        if paginated { position -= 1 }   // the corner, always ahead of this slot
        return position
    }

    @ViewBuilder
    private func slot(at index: Int, position: Int, in layout: RingLayout, site: Site?) -> some View {
        let frame = layout.rect(at: index)
        // Only the next square in line lights up, since sites pack in order
        // rather than going wherever they're clicked.
        let isNextFree = position == model.nextFreeSlot
        let highlighted = site == nil
            ? (model.canPlaceCurrentSite && isNextFree)
            : site?.id == model.selectedID

        FaviconSquareView(site: site, size: layout.square,
                          highlighted: highlighted, ruled: model.isDense)
            .contentShape(Rectangle())
            .help(site?.displayName ?? (model.canPlaceCurrentSite ? "Save this site here" : "Add a site"))
            .onTapGesture {
                model.stopTour()   // a deliberate click ends the tour
                if let site {
                    model.open(site)
                } else if model.canPlaceCurrentSite {
                    model.placeCurrentSite()
                } else {
                    model.sheet = .add(nil)
                }
            }
            .contextMenu {
                if let site {
                    Button("Open") { model.open(site) }
                    Button("Open in Default Browser") {
                        if let url = site.resolvedURL { NSWorkspace.shared.open(url) }
                    }
                    Divider()
                    Button("Show Notes") {
                        // Notes follow whatever's on screen, so show the site
                        // first, then bring the notebook up.
                        model.open(site)
                        openWindow(id: NotesWindowID)
                    }
                    Button("New Letter Colour") { model.randomizeColor(of: site) }
                    Button("Edit…") { model.sheet = .edit(site) }
                    Button("Remove…", role: .destructive) { model.requestRemoval(of: site) }
                } else {
                    if model.canPlaceCurrentSite {
                        Button("Save Current Site") { model.placeCurrentSite() }
                    }
                    Button("Add Site…") { model.sheet = .add(nil) }
                }
            }
            .modifier(SlotDragAndDrop(site: site, index: position, model: model))
            .offset(x: frame.minX, y: frame.minY)
    }

    // MARK: - Viewport

    private func viewport(in layout: RingLayout) -> some View {
        let frame = layout.viewport

        return ZStack {
            Color.viewportBackground

            if model.hasContent {
                WebViewport(engine: model.engine)
            } else {
                Text(model.sites.isEmpty
                     ? "Click a square along the edge to add a friend's site to this frame."
                     : "Click a favicon to open it here.")
                    .font(.system(size: 15))
                    .foregroundColor(.placeholderText)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.slotBorder, lineWidth: 1)
        )
        .offset(x: frame.minX, y: frame.minY)
    }

    /// A site you've written something about says so. Drawn as a sibling after
    /// the viewport rather than as an overlay on it — the web view is a real
    /// AppKit view and paints over anything layered onto it.
    @ViewBuilder
    private func noteBadge(in layout: RingLayout) -> some View {
        if let site = model.siteForNotes, site.notes?.isEmpty == false {
            let viewport = layout.viewport
            let size: CGFloat = 17
            let margin: CGFloat = 8

            NoteBadge()
                .onTapGesture { openWindow(id: NotesWindowID) }
                .onHover { inside in
                    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
                .help("Notes on \(site.displayName)")
                .offset(x: viewport.maxX - size - margin, y: viewport.maxY - size - margin)
        }
    }
}

/// A little page of yellow paper, marking a site that has notes on it.
private struct NoteBadge: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.notePaper)

            NoteLinesGlyph()
                .stroke(Color.black.opacity(0.5), lineWidth: 1)
                .frame(width: 9, height: 7)
        }
        .frame(width: 17, height: 17)
        .overlay(Rectangle().stroke(Color.slotBorder, lineWidth: 1))
    }
}

private struct NoteLinesGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = 3

        for row in 0..<rows {
            let y = rect.minY + rect.height / CGFloat(rows - 1) * CGFloat(row)
            // Last line stops short, the way a written line does.
            let width = row == rows - 1 ? rect.width * 0.6 : rect.width
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.minX + width, y: y))
        }
        return path
    }
}

/// An AppKit context menu for views SwiftUI's .contextMenu can't reach, such as
/// anything living inside a toolbar item.
struct RightClickMenu: NSViewRepresentable {
    let items: [(title: String, action: () -> Void)]

    func makeNSView(context: Context) -> NSView {
        let view = MenuHostView()
        view.items = items
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MenuHostView)?.items = items
    }

    final class MenuHostView: NSView {
        var items: [(title: String, action: () -> Void)] = []

        override func rightMouseDown(with event: NSEvent) {
            let menu = NSMenu()
            for (index, item) in items.enumerated() {
                let entry = NSMenuItem(title: item.title,
                                       action: #selector(choose(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.tag = index
                menu.addItem(entry)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func choose(_ sender: NSMenuItem) {
            guard items.indices.contains(sender.tag) else { return }
            items[sender.tag].action()
        }
    }
}

/// Dropping an exported frame's JSON on the window loads it as a new frame.
private struct FrameFileDropDelegate: DropDelegate {
    let model: BrowserModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: url) else { return }

            Task { @MainActor in
                model.loadFrame(from: data,
                                fallbackName: url.deletingPathExtension().lastPathComponent)
            }
        }
        return true
    }
}

/// A frame around a picture, both drawn as outlines and open in the middle:
/// outer rule, gap, then a thinner rule around the picture. Four nested rects
/// under an even-odd fill alternate fill, hole, fill, hole.
private struct FrameGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let rule = max(1, (side * 0.08).rounded())
        let gap = max(1, (side * 0.17).rounded())
        let pictureRule = max(1, (side * 0.06).rounded())

        var path = Path()
        path.addRect(rect)
        path.addRect(rect.insetBy(dx: rule, dy: rule))
        path.addRect(rect.insetBy(dx: rule + gap, dy: rule + gap))
        path.addRect(rect.insetBy(dx: rule + gap + pictureRule, dy: rule + gap + pictureRule))
        return path
    }
}

/// An Archimedean spiral, wound out from the middle: the radius grows in step
/// with the angle, so the turns stay evenly spaced.
private struct SpiralGlyph: Shape {
    var turns: Double = 2.4

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outermost = min(rect.width, rect.height) / 2
        let sweep = turns * 2 * .pi
        let step = Double.pi / 24   // fine enough that the line reads as curved

        var path = Path()
        var angle = 0.0

        while angle <= sweep {
            let radius = outermost * angle / sweep
            let point = CGPoint(x: centre.x + CoreGraphics.cos(angle) * radius,
                                y: centre.y + CoreGraphics.sin(angle) * radius)

            if angle == 0 { path.move(to: point) } else { path.addLine(to: point) }
            angle += step
        }
        return path
    }
}

/// Drawn rather than taken from SF Symbols, whose play/pause glyphs have
/// rounded corners baked in.
private struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PauseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let bar = rect.width * 0.36
        var path = Path()
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: bar, height: rect.height))
        path.addRect(CGRect(x: rect.maxX - bar, y: rect.minY, width: bar, height: rect.height))
        return path
    }
}

/// SwiftUI can re-show the default window title over whatever titleVisibility
/// we set on the NSWindow, so on macOS 15+ the item is removed outright. On
/// Sonoma that API doesn't exist and WindowStyler's titleVisibility is enough,
/// since nothing here sets a navigationTitle for SwiftUI to restore.
private struct HideToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

/// A sheet gets its own window, and doesn't inherit the light appearance the
/// main one is pinned to — so on a Mac set to dark mode its text comes up white
/// on the frame's light gray, near enough invisible. Pinning each sheet the same
/// way fixes the AppKit controls inside it too, which ignore SwiftUI's
/// colorScheme on its own.
private struct SheetStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.appearance = NSAppearance(named: .aqua) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.appearance = NSAppearance(named: .aqua) }
    }
}

extension View {
    /// Keeps a sheet on the app's own light gray, whatever the system is set to.
    func lightSheet() -> some View {
        background(SheetStyler())
            .environment(\.colorScheme, .light)
    }
}

/// Paints the title bar the same gray as the frame, so the window reads as one
/// continuous surface.
private struct WindowStyler: NSViewRepresentable {
    /// Set on the window for the Window menu, but drawn by the toolbar item.
    /// Using .navigationTitle instead would keep un-hiding the system title,
    /// showing the URL twice.
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.title = title
        window.backgroundColor = .frameBackground
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden   // redrawn as a toolbar item instead
        // The frame is a light gray, so pin the window light: a dark-mode title
        // bar would draw white text on it.
        window.appearance = NSAppearance(named: .aqua)
    }
}

/// Drag a favicon onto another square to reorder the ring.
private struct SlotDragAndDrop: ViewModifier {
    let site: Site?
    let index: Int
    let model: BrowserModel

    func body(content: Content) -> some View {
        content
            .if(site != nil) { $0.siteDragSource(site!) }
            .onDrop(of: [.text], delegate: SiteMoveDropDelegate(index: index, model: model))
    }
}

private extension View {
    @ViewBuilder
    func `if`<Result: View>(_ condition: Bool, transform: (Self) -> Result) -> some View {
        if condition { transform(self) } else { self }
    }
}

#Preview {
    ContentView()
        .environmentObject(BrowserModel())
        .frame(width: 900, height: 700)
}
