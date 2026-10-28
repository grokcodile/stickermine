import Foundation

/// The changes editing makes (spec sections 10 and 11). Each returns false,
/// changing nothing, when what it names is unknown or already so.
extension Library {
    /// Moves the placement to the end of its display's list: the front of
    /// that display's z-order.
    @discardableResult
    mutating func bringToFront(_ id: UUID) -> Bool {
        guard let key = displayKey(containing: id), var record = displays[key],
              let index = record.placements.firstIndex(where: { $0.id == id }),
              index < record.placements.count - 1
        else { return false }
        record.placements.append(record.placements.remove(at: index))
        displays[key] = record
        return true
    }

    /// Changes one placement wherever it is.
    @discardableResult
    mutating func updatePlacement(_ id: UUID, _ change: (inout Placement) -> Void) -> Bool {
        guard let key = displayKey(containing: id), var record = displays[key],
              let index = record.placements.firstIndex(where: { $0.id == id })
        else { return false }
        change(&record.placements[index])
        displays[key] = record
        return true
    }

    /// Moves the placement to the front of the display record `key` (a drop
    /// on another display).
    @discardableResult
    mutating func movePlacement(_ id: UUID, toDisplay key: String) -> Bool {
        guard displays[key] != nil, let placement = removePlacement(id) else { return false }
        displays[key]?.placements.append(placement)
        return true
    }

    /// Restyles the placement and makes the style its sticker's `lastStyle`
    /// (spec section 12).
    @discardableResult
    mutating func restyle(_ id: UUID, to style: StickerStyle) -> Bool {
        guard let sticker = placement(id)?.sticker, placement(id)?.style != style else { return false }
        updatePlacement(id) { $0.style = style }
        if let index = stickers.firstIndex(where: { $0.id == sticker }) {
            stickers[index].lastStyle = style
        }
        return true
    }
}
