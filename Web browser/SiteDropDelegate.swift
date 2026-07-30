//
//  SiteDropDelegate.swift
//  Web browser
//
//  Rearranging is a move, not a copy. SwiftUI's .dropDestination always
//  proposes .copy, which is what puts the green + on the cursor; a DropDelegate
//  is the only way to say otherwise.
//

import SwiftUI
import UniformTypeIdentifiers

struct SiteMoveDropDelegate: DropDelegate {
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
                model.move(id: id, toSlot: index)
            }
        }
        return true
    }
}

extension View {
    /// Marks a favicon as the thing being moved.
    func siteDragSource(_ site: Site) -> some View {
        onDrag {
            NSItemProvider(object: site.id.uuidString as NSString)
        } preview: {
            FaviconSquareView(site: site, size: 28, highlighted: false)
        }
    }
}
