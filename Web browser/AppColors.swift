//
//  AppColors.swift
//  Web browser
//
//  Created by Elliott Cost on 1/19/26.
//

import SwiftUI

extension NSColor {
    /// The frame the favicon squares sit on. Also painted into the title bar,
    /// so it lives here as an NSColor and Color derives from it.
    static let frameBackground = NSColor(red: 171/255, green: 171/255, blue: 171/255, alpha: 1)
}

extension Color {
    static let frameBackground = Color(nsColor: .frameBackground)
    /// An unclaimed square along the border: a touch lighter than the frame,
    /// carrying no outline of its own.
    static let slotEmpty = Color(red: 200/255, green: 200/255, blue: 200/255)
    /// Backing behind a favicon, so transparent icons stay legible.
    static let slotFilled = Color.white
    static let viewportBackground = Color(red: 216/255, green: 216/255, blue: 216/255)
    static let placeholderText = Color(red: 0.45, green: 0.45, blue: 0.45)
    /// The notes page: legal-pad yellow rather than plain white.
    static let notePaper = Color(red: 253/255, green: 246/255, blue: 197/255)
    /// Rule under the title bar.
    static let separator = Color.black.opacity(0.25)
    /// The fixed play/pause square in the top-right corner. Deliberately the
    /// same blue as the selection outline.
    static let tourButton = selectionBorder
    /// Outline every square carries.
    static let slotBorder = Color.black.opacity(0.18)
    /// Rule between squares packed edge to edge. Lighter than the outlines round
    /// bigger things — there are hundreds of these, and they only need to say
    /// where one square ends and the next begins.
    static let slotRule = Color.black.opacity(0.09)
    /// Outline around a frame tile in the grid — heavier, since a whole frame
    /// needs a firmer edge than a single square.
    static let frameOutline = Color.black.opacity(0.22)
    /// Border on the square whose site is currently open. The browser default
    /// link blue rather than the macOS accent blue.
    static let selectionBorder = Color(red: 0/255, green: 0/255, blue: 238/255)
    /// The URL bar's box: lighter than the frame it sits on.
    static let urlBarBackground = Color(red: 194/255, green: 194/255, blue: 194/255)
}
