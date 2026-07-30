//
//  RingLayout.swift
//  Web browser
//
//  Geometry for the ring of squares around the edge of the window, and the
//  viewport they enclose. Pure math: given a size, it says how many squares
//  fit and where each one goes.
//

import CoreGraphics

struct RingLayout {
    let size: CGSize
    let square: CGFloat
    let minGap: CGFloat

    let columns: Int
    let rows: Int
    private let gapX: CGFloat
    private let gapY: CGFloat

    init(size: CGSize, square: CGFloat, minGap: CGFloat) {
        let width = max(size.width, 0)
        let height = max(size.height, 0)
        self.size = CGSize(width: width, height: height)
        self.square = square
        self.minGap = minGap

        // How many squares fit along each edge at the minimum gap...
        columns = max(2, Int((width + minGap) / (square + minGap)))
        rows = max(2, Int((height + minGap) / (square + minGap)))
        // ...then spread the leftover space evenly between them.
        gapX = columns > 1 ? max(0, (width - CGFloat(columns) * square) / CGFloat(columns - 1)) : 0
        gapY = rows > 1 ? max(0, (height - CGFloat(rows) * square) / CGFloat(rows - 1)) : 0
    }

    /// The ring that holds `siteCount` sites all at once, found by shrinking
    /// the squares — and the gaps along with them, so the ring keeps its
    /// proportions — a point at a time. Never bigger than the size that was
    /// asked for, and never smaller than stays legible: past that the squares
    /// come back at the floor and the caller's pagination takes over.
    static func fitting(siteCount: Int, in size: CGSize,
                        preferred: CGFloat, minGap: CGFloat) -> RingLayout {
        let smallest: CGFloat = 10
        var square = max(smallest, preferred.rounded())

        while true {
            // Proportional to how far the square has shrunk, so tiny squares
            // don't sit in gaps wider than they are.
            let gap = max(2, (minGap * square / preferred).rounded())
            let side = minGap == 0 ? RingLayout.evenSquare(near: square, in: size) : square
            let ring = RingLayout(size: size, square: side, minGap: min(gap, minGap))

            // One square is the tour button and holds no site.
            if ring.slotCount - 1 >= siteCount || square <= smallest { return ring }
            square -= 1
        }
    }

    /// A square asked to leave no gaps still leaves them, unless it happens to
    /// divide the window: whatever's left over gets spread between the squares
    /// as hairlines of frame showing through. So the size gives a little
    /// instead — the largest square within a few points that divides both edges
    /// most evenly, which puts the leftover under a pixel and the squares
    /// properly shoulder to shoulder.
    ///
    /// Only ever shrinks, so a ring sized to fit a number of sites keeps
    /// holding them.
    static func evenSquare(near preferred: CGFloat, in size: CGSize) -> CGFloat {
        var best = preferred
        var least = CGFloat.greatestFiniteMagnitude

        // Nearest first, so a tie keeps the square closest to the one asked for.
        var give: CGFloat = 0
        while give <= min(4, preferred / 4) {
            let square = preferred - give
            let slack = max(leftover(along: size.width, square: square),
                            leftover(along: size.height, square: square))

            if slack < least - 0.01 {
                least = slack
                best = square
                if slack < 0.05 { break }   // near enough exact
            }
            give += 0.25
        }
        return best
    }

    /// The gap each square would end up carrying along an edge of this length.
    private static func leftover(along length: CGFloat, square: CGFloat) -> CGFloat {
        let count = max(2, Int(length / square))
        guard count > 1 else { return 0 }
        return max(0, (length - CGFloat(count) * square) / CGFloat(count - 1))
    }

    /// Squares on the left and right edges, excluding the corners (which belong
    /// to the top and bottom rows).
    private var sideCount: Int { max(0, rows - 2) }

    var slotCount: Int { 2 * columns + 2 * sideCount }

    /// Slot positions run clockwise from the top-left corner.
    func rect(at index: Int) -> CGRect {
        let origin: CGPoint

        switch index {
        case ..<columns:
            // Top edge, left to right.
            origin = CGPoint(x: CGFloat(index) * (square + gapX), y: 0)

        case columns ..< (columns + sideCount):
            // Right edge, top to bottom.
            let step = index - columns
            origin = CGPoint(x: size.width - square, y: CGFloat(step + 1) * (square + gapY))

        case (columns + sideCount) ..< (2 * columns + sideCount):
            // Bottom edge, right to left.
            let step = index - columns - sideCount
            origin = CGPoint(x: size.width - square - CGFloat(step) * (square + gapX),
                             y: size.height - square)

        default:
            // Left edge, bottom to top.
            let step = index - 2 * columns - sideCount
            origin = CGPoint(x: 0, y: size.height - square - CGFloat(step + 1) * (square + gapY))
        }

        return CGRect(origin: origin, size: CGSize(width: square, height: square))
    }

    var viewport: CGRect {
        let inset = square + max(minGap, min(gapX, gapY))
        return CGRect(x: inset,
                      y: inset,
                      width: max(0, size.width - 2 * inset),
                      height: max(0, size.height - 2 * inset))
    }
}

/// How a frame's sites are spread around a ring that can't hold all of them at
/// once. The top-right corner is always the tour button; past that, the
/// top-left corner turns into a page number, so a paginated ring shows one
/// site fewer than a plain one.
struct RingPaging {
    /// Sites shown at a time.
    let capacity: Int
    let pageCount: Int
    /// Clamped: shrinking the window, or the frame, can strand the page the
    /// model remembers past the end.
    let page: Int

    var isPaginated: Bool { pageCount > 1 }

    init(siteCount: Int, slots: Int, page requested: Int) {
        let whole = max(1, slots - 1)   // the tour button

        if siteCount <= whole {
            capacity = whole
            pageCount = 1
        } else {
            let paged = max(1, slots - 2)   // the tour button and the page number
            capacity = paged
            pageCount = (siteCount + paged - 1) / paged
        }
        page = min(max(requested, 0), pageCount - 1)
    }

    /// Where the site shown at `position` on this page sits in the frame.
    func frameIndex(of position: Int) -> Int { page * capacity + position }

    /// Which page a site in the frame is shown on.
    func pageIndex(of frameIndex: Int) -> Int { frameIndex / capacity }
}
