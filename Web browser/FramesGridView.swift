//
//  FramesGridView.swift
//  Web browser
//
//  All your frames at once. Each tile draws a miniature of the frame's own
//  ring rather than a page preview — the favicons are the thing you recognise.
//

import SwiftUI
import UniformTypeIdentifiers

struct FramesGridView: View {
    @ObservedObject var model: BrowserModel

    @FocusState private var focused: Bool

    private let narrowest: CGFloat = 200
    private let spacing: CGFloat = 14
    private let margin: CGFloat = 20

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: narrowest, maximum: 280), spacing: spacing)]
    }

    var body: some View {
        // The grid decides its own column count from the width available, so the
        // same sum is worked out here for the arrow keys to step by.
        GeometryReader { geometry in
            let across = columnCount(for: geometry.size.width)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(Array(model.frames.enumerated()), id: \.element.id) { index, frame in
                            FrameTile(frame: frame,
                                      index: index,
                                      isSelected: frame.id == model.selectedFrameID,
                                      model: model)
                                .id(frame.id)
                        }

                        NewFrameTile(model: model)
                    }
                    .padding(margin)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onAppear { focused = true }
                .onKeyPress(.leftArrow) { move(by: -1) }
                .onKeyPress(.rightArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -across) }
                .onKeyPress(.downArrow) { move(by: across) }
                // Stepping off the bottom of the window should bring the frame
                // you've landed on into view.
                .onChange(of: model.selectedFrameID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    /// What LazyVGrid's .adaptive does with the space: as many columns of at
    /// least the minimum width as will fit, once the margins are taken off.
    private func columnCount(for width: CGFloat) -> Int {
        let usable = max(0, width - 2 * margin)
        return max(1, Int((usable + spacing) / (narrowest + spacing)))
    }

    /// Moves the highlight along the grid, stopping at either end rather than
    /// wrapping — a run of presses shouldn't loop you back to the start.
    private func move(by delta: Int) -> KeyPress.Result {
        guard !model.frames.isEmpty else { return .ignored }

        guard let current = model.frames.firstIndex(where: { $0.id == model.selectedFrameID }) else {
            model.selectedFrameID = model.frames.first?.id
            return .handled
        }

        let next = min(max(current + delta, 0), model.frames.count - 1)
        model.selectedFrameID = model.frames[next].id
        return .handled
    }
}

private extension View {
    /// Pointing-hand cursor on hover. SwiftUI's .pointerStyle is macOS 15+, so
    /// this sets the AppKit cursor directly to keep working on Sonoma. Uses
    /// set() rather than push()/pop(), which can leave the stack unbalanced if
    /// the view goes away while hovered.
    func linkCursor() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

private struct FrameTile: View {
    let frame: Frame
    let index: Int
    let isSelected: Bool
    let model: BrowserModel


    var body: some View {
        FramePreview(frame: frame) {
            VStack(spacing: 3) {
                Text(frame.displayName)
                    .font(.system(size: 15))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let author = frame.displayAuthor {
                    Text("by \(author)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .lineLimit(1)
                }

                Text("\(frame.sites.count) site\(frame.sites.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
            .padding(.horizontal, 10)
        }
            .aspectRatio(1, contentMode: .fit)
            .background(Color.frameBackground)
            .overlay(
                // Only what's selected is marked out; hovering leaves it alone.
                Rectangle()
                    .stroke(isSelected ? Color.selectionBorder : Color.frameOutline,
                            lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        // Double click opens. Selection runs as a *simultaneous* gesture so it
        // fires on the first click rather than waiting out the double-click
        // interval to find out whether a second one is coming.
        .onTapGesture(count: 2) { model.select(frame) }
        .simultaneousGesture(TapGesture().onEnded {
            model.selectedFrameID = frame.id
        })
        .linkCursor()
        .onDrag {
            NSItemProvider(object: frame.id.uuidString as NSString)
        } preview: {
            FramePreview(frame: frame) { EmptyView() }
                .frame(width: 90, height: 90)
                .background(Color.frameBackground)
        }
        .onDrop(of: [.text], delegate: FrameMoveDropDelegate(index: index, model: model))
        .contextMenu {
            Button("Open") { model.select(frame) }
            Button("Rename…") { model.renamingFrame = frame }
            Button("Export…") { model.exportFrame(frame) }
            Divider()
            Button("Delete…", role: .destructive) { model.requestRemoval(of: frame) }
        }
        .help(frame.displayName)
    }
}

/// Always last in the grid: an empty frame that makes another one.
private struct NewFrameTile: View {
    let model: BrowserModel


    var body: some View {
        // No ring at all here — an empty frame's worth of blank squares would
        // read as a frame that exists rather than one you're about to make.
        Rectangle()
            .fill(Color.frameBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                PlusGlyph()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 72, height: 72)
            }
        .overlay(Rectangle().stroke(Color.frameOutline, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { model.newFrame() }
        .linkCursor()
        .help("New frame")
    }
}

/// Its bars are a set width rather than a proportion of its size, so drawing it
/// large makes a bigger plus rather than a heavier one.
private struct PlusGlyph: Shape {
    var thickness: CGFloat = 2.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: rect.minX, y: rect.midY - thickness / 2,
                            width: rect.width, height: thickness))
        path.addRect(CGRect(x: rect.midX - thickness / 2, y: rect.minY,
                            width: thickness, height: rect.height))
        return path
    }
}

/// Rearranging is a move, not a copy — same reason as the favicon squares.
private struct FrameMoveDropDelegate: DropDelegate {
    let index: Int
    let model: BrowserModel

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String,
                  let id = UUID(uuidString: string) else { return }
            Task { @MainActor in
                model.moveFrame(id: id, to: index)
            }
        }
        return true
    }
}

/// The frame's ring, shrunk down. Same geometry as the real thing, with
/// whatever you like in the middle.
private struct FramePreview<Center: View>: View {
    let frame: Frame
    @ViewBuilder let center: Center

    // Bigger than the ring's own squares would scale to, so a tile shows a
    // handful of a frame's favicons rather than all of them — enough to
    // recognise it by. Whatever doesn't fit simply isn't drawn.
    private let square: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            // Packed the way the frame itself is: out to the edge, no gaps, at
            // whatever size divides the tile most evenly.
            let content = geometry.size
            let side = RingLayout.evenSquare(near: square, in: content)
            let layout = RingLayout(size: content, square: side, minGap: 0)
            let placed = Dictionary(uniqueKeysWithValues: frame.sites.enumerated().map { ($0.offset, $0.element) })
            // No tour button in a preview, so every square holds a site.
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: content.width, height: content.height)

                ForEach(0..<layout.slotCount, id: \.self) { index in
                    let rect = layout.rect(at: index)

                    FaviconSquareView(site: placed[index], size: side,
                                      highlighted: false, ruled: true, interactive: false)
                        .frame(width: side, height: side)
                        .offset(x: rect.minX, y: rect.minY)
                }

                // Whatever the caller wants sits where the pages would be,
                // straight on the frame rather than on a viewport panel.
                Color.clear
                    .overlay { center }
                    .frame(width: layout.viewport.width, height: layout.viewport.height)
                    .offset(x: layout.viewport.minX, y: layout.viewport.minY)
            }
            .frame(width: content.width, height: content.height, alignment: .topLeading)
        }
    }
}

/// Small sheet for renaming a frame.
struct RenameFrameView: View {
    let model: BrowserModel
    let frame: Frame

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var author: String

    init(model: BrowserModel, frame: Frame) {
        self.model = model
        self.frame = frame
        _name = State(initialValue: frame.name)
        // A frame from before authors existed is signed by you on the next edit.
        _author = State(initialValue: frame.displayAuthor ?? BrowserModel.thisUser)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Title of Frame")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)

            EditableTextField(text: $name,
                              placeholder: "Title of frame",
                              font: .systemFont(ofSize: 13),
                              selectAllOnFocus: true,
                              onSubmit: save)
                .frame(height: 18)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Rectangle().fill(Color.urlBarBackground))

            VStack(alignment: .leading, spacing: 6) {
                Text("By")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.45))

                EditableTextField(text: $author,
                                  placeholder: "Who made it",
                                  font: .systemFont(ofSize: 13),
                                  onSubmit: save)
                    .frame(height: 18)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Rectangle().fill(Color.urlBarBackground))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Color.frameBackground)
    }

    private func save() {
        model.rename(frame, to: name, author: author)
        dismiss()
    }
}
