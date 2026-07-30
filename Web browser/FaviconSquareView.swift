//
//  FaviconSquareView.swift
//  Web browser
//
//  One square along the border: a friend's favicon, or an empty slot.
//

import SwiftUI

/// A band down the right and bottom edges, mitred at the corners it meets, so a
/// flat square reads as lit from the upper left. Shared with the page number in
/// the ring's top-left corner, which is drawn as a letter square too.
struct InnerBevel: Shape {
    var thickness: CGFloat = 0.1

    func path(in rect: CGRect) -> Path {
        let depth = (min(rect.width, rect.height) * thickness).rounded()
        let inner = rect.insetBy(dx: depth, dy: depth)

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: inner.minX, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.minY))
        path.closeSubpath()
        return path
    }
}

extension Site {
    /// A dark colour picked from the domain for letter squares. Deliberately
    /// hashed by hand — Swift's own hashValue is seeded per launch, so the
    /// colours would change every time you opened the app.
    /// A re-rolled colour if there is one, otherwise the domain's own hash.
    private var resolvedColorSeed: UInt64 {
        if let colorSeed { return colorSeed }

        var hash: UInt64 = 5381
        for byte in host.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return hash
    }

    /// Hue, saturation and brightness each off a separate slice of the hash,
    /// so the squares land anywhere in the colour space rather than all
    /// reading as one tone.
    private var monogramHSB: (hue: Double, saturation: Double, brightness: Double) {
        let seed = resolvedColorSeed
        return (hue: Double(seed % 360) / 360,
                saturation: 0.35 + Double((seed / 360) % 60) / 100,
                brightness: 0.38 + Double((seed / 23_400) % 57) / 100)
    }

    var monogramColor: Color {
        let colour = monogramHSB
        return Color(hue: colour.hue, saturation: colour.saturation, brightness: colour.brightness)
    }

    /// Whichever of black or white reads against that background.
    var monogramTextColor: Color {
        monogramHSB.brightness > 0.66 ? .black : .white
    }
}

struct FaviconSquareView: View {
    let site: Site?
    let size: CGFloat
    /// The open site, or an empty square offering to hold the current one.
    let highlighted: Bool
    /// Squares packed edge to edge need a rule to tell them apart. Spaced out,
    /// the gaps do that on their own and an outline is just noise.
    var ruled = false
    /// False in previews, where the squares aren't targets in their own right.
    var interactive = true

    @ObservedObject private var loader = FaviconLoader.shared
    @State private var icon: NSImage?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if site == nil {
                // Under the pointer an empty square colours in rather than
                // taking an outline, which would sit oddly next to the outline
                // that means something.
                Rectangle()
                    .fill(isHovering ? Color.accentColor : Color.slotEmpty)
            }

            if let site {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(site.monogramColor)
                        .overlay {
                            // Shaded down the right and bottom, so the square
                            // reads as raised.
                            InnerBevel()
                                .fill(Color.black.opacity(0.2))
                        }
                        .overlay {
                            Text(site.monogram)
                                .font(.custom("Times New Roman", size: size * 0.52))
                                .foregroundColor(site.monogramTextColor)
                        }
                }
            }
        }
        .overlay(
            Rectangle()
                .stroke(borderColor, lineWidth: highlighted ? 2 : 1)
        )
        .frame(width: size, height: size)
        .onHover { inside in
            guard interactive else { return }
            isHovering = inside
            // SwiftUI's .pointerStyle is macOS 15+, so set the AppKit cursor.
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .task(id: fetchKey) {
            guard let site else {
                icon = nil
                return
            }
            icon = await loader.icon(for: site)
        }
    }

    /// The blue border marks the open site, and an empty square offering to
    /// hold the current one. Nothing else carries an outline unless the squares
    /// are packed together, where a faint rule is all that separates them.
    private var borderColor: Color {
        if highlighted { return .selectionBorder }

        // Favicons sit straight against one another — they're different enough
        // to tell apart on their own. It's the empty squares, all the same gray,
        // that need a rule between them.
        return ruled && site == nil ? .slotRule : .clear
    }

    /// Re-runs the fetch when the site changes, or when icons are refreshed.
    private var fetchKey: String {
        "\(loader.generation)|\(site?.url ?? "")"
    }
}
