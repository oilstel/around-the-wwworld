//
//  EditableTextField.swift
//  Web browser
//
//  An NSTextField wrapped for SwiftUI. SwiftUI's own TextField is unreliable in
//  the places this app needs one — inside a toolbar item, and inside rows that
//  are also drag sources — where it loses focus or never receives the click.
//

import AppKit
import SwiftUI

struct EditableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont
    var alignment: NSTextAlignment = .left
    /// Select the whole contents when focus arrives, so typing replaces it.
    var selectAllOnFocus = false
    var onSubmit: () -> Void = {}
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = SelectOnFocusTextField()
        field.selectsAllOnFocus = selectAllOnFocus
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = alignment
        field.font = font
        field.textColor = .black
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.stringValue = text
        applyPlaceholder(to: field)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self

        // Touch nothing while the field is being edited. Beginning to edit
        // flips state in the owning view, which re-runs this method — and
        // reassigning the string or the placeholder mid-edit resets the field
        // editor, wiping the select-all that a click just made.
        guard field.currentEditor() == nil else { return }

        if field.stringValue != text {
            field.stringValue = text
        }
        applyPlaceholder(to: field)
    }

    private func applyPlaceholder(to field: NSTextField) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: font,
                         .foregroundColor: NSColor(white: 0.45, alpha: 1),
                         .paragraphStyle: style])
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: EditableTextField

        init(_ parent: EditableTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onEditingChanged(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEditingChanged(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

/// The cell and the field editor otherwise lay text out at slightly different
/// origins, so text nudges up by a pixel the moment you click into it. Pinning
/// the drawing rect to a centred, text-height band keeps both states identical.
private final class SteadyTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        let inset = (base.height - textHeight) / 2
        guard inset > 0 else { return base }

        return NSRect(x: base.origin.x,
                      y: base.origin.y + inset,
                      width: base.width,
                      height: textHeight)
    }
}

private final class SelectOnFocusTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { SteadyTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    var selectsAllOnFocus = false

    /// Covers focus arriving by keyboard (tab).
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, selectsAllOnFocus {
            selectEverythingSoon()
        }
        return accepted
    }

    /// Covers focus arriving by click.
    override func mouseDown(with event: NSEvent) {
        let wasAlreadyEditing = currentEditor() != nil
        super.mouseDown(with: event)
        if selectsAllOnFocus, !wasAlreadyEditing {
            selectEverythingSoon()
        }
    }

    /// AppKit runs its own event loop while tracking a click in a text field,
    /// which means main-queue work can execute *before* the mouse is released
    /// — and the release then collapses the selection to a caret. That's the
    /// "flashes selected, then doesn't" behaviour. Selecting repeatedly,
    /// ending after a short delay, guarantees the last word.
    private func selectEverythingSoon() {
        selectText(nil)
        DispatchQueue.main.async { [weak self] in
            self?.selectText(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.selectText(nil)
        }
    }
}
