import AppKit
import XCTest
@testable import LidAwakeCore

final class StableMenuTests: XCTestCase {
    private let action = #selector(NSObject.description)

    func testRepeatedPollsDoNotMutateMenuOrReplaceItsItems() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        let entries: [MenuEntry] = [
            MenuEntry(id: "status", title: "On AC power · staying awake"),
            .separator("power-separator"),
            MenuEntry(id: "ac", title: "Connected to Power", action: action, state: .on, indentationLevel: 1, symbol: "powerplug.fill"),
            MenuEntry(id: "quit", title: "Quit", action: action)
        ]
        renderer.update(entries, target: self)
        let originalItems = menu.items
        let originalIcon = menu.items[2].image
        XCTAssertNotNil(originalIcon)
        var notifications = 0
        let observers = [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification, NSMenu.didChangeItemNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: menu, queue: nil) { _ in notifications += 1 }
        }
        defer { observers.forEach(NotificationCenter.default.removeObserver) }
        for _ in 0..<5 { renderer.update(entries, target: self) }
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(menu.numberOfItems, originalItems.count)
        for (original, current) in zip(originalItems, menu.items) { XCTAssertTrue(original === current) }
        XCTAssertTrue(menu.items[2].isEnabled)
        XCTAssertEqual(menu.items[2].indentationLevel, 1)
        XCTAssertTrue(menu.items[2].image === originalIcon)
    }

    func testDisablingDependentControlsPreservesTheirCheckmarksAndIndentation() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        func entries(enabled: Bool) -> [MenuEntry] {
            [MenuEntry(id: "enabled", title: "Enable LidAwake", action: action, state: enabled ? .on : .off),
             MenuEntry(id: "ac", title: "Connected to Power", action: action, state: .on, enabled: enabled, indentationLevel: 1),
             MenuEntry(id: "battery", title: "On Battery", action: action, enabled: enabled, indentationLevel: 1)]
        }
        renderer.update(entries(enabled: true), target: self)
        let original = menu.items
        for enabled in [false, true] {
            renderer.update(entries(enabled: enabled), target: self)
            XCTAssertTrue(menu.items[0].isEnabled)
            XCTAssertEqual(menu.items[0].state, enabled ? .on : .off)
            XCTAssertEqual(menu.items[1].state, .on)
            XCTAssertEqual(menu.items[2].state, .off)
            for index in 1...2 {
                XCTAssertTrue(menu.items[index] === original[index])
                XCTAssertEqual(menu.items[index].isEnabled, enabled)
                XCTAssertEqual(menu.items[index].indentationLevel, 1)
            }
        }
    }

    func testRealStateChangesUpdateExistingItemsWithoutMovingRows() {
        let menu = NSMenu()
        let renderer = StableMenu(menu: menu)
        renderer.update([
            MenuEntry(id: "status", title: "On AC power · staying awake"),
            MenuEntry(id: "ac", title: "Stay Awake on AC Power", action: action, state: .on)
        ], target: self)
        let original = menu.items
        renderer.update([
            MenuEntry(id: "status", title: "On battery · sleep enabled"),
            MenuEntry(id: "ac", title: "Stay Awake on AC Power", action: action, state: .off)
        ], target: self)
        XCTAssertTrue(menu.items[0] === original[0])
        XCTAssertTrue(menu.items[1] === original[1])
        XCTAssertEqual(menu.items[0].title, "On battery · sleep enabled")
        XCTAssertEqual(menu.items[1].state, .off)
    }

    func testErrorRowDoesNotRecreateOtherItems() {
        let menu = NSMenu()
        let renderer = StableMenu(menu: menu)
        let status = MenuEntry(id: "status", title: "Sleep enabled")
        let quit = MenuEntry(id: "quit", title: "Quit", action: action)
        renderer.update([status, quit], target: self)
        let original = menu.items
        renderer.update([status, MenuEntry(id: "error", title: "Needs attention"), quit], target: self)
        XCTAssertEqual(menu.numberOfItems, 3)
        XCTAssertTrue(menu.items[2] === original[1])
        renderer.update([status, quit], target: self)
        XCTAssertEqual(menu.numberOfItems, 2)
        XCTAssertTrue(menu.items[0] === original[0])
        XCTAssertTrue(menu.items[1] === original[1])
    }

    func testCompactAndStandardRowsKeepOneImagePerSymbolAndSize() throws {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        let entries = [
            MenuEntry(id: "compact", title: "Connected to Power", action: action, style: .compactToggle, symbol: "powerplug.fill"),
            MenuEntry(id: "standard", title: "Plug", action: action, symbol: "powerplug.fill")
        ]
        func size(_ points: CGFloat) -> NSSize? {
            NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: points, weight: .regular))?.size
        }
        renderer.update(entries, target: self)
        let row = try XCTUnwrap(menu.items[0].view as? SwitchMenuRow)
        let compactImage = try XCTUnwrap(row.subviews.compactMap { $0 as? NSImageView }.first?.image)
        let standardImage = try XCTUnwrap(menu.items[1].image)
        XCTAssertNil(menu.items[0].image)
        XCTAssertNotNil(size(11))
        XCTAssertEqual(compactImage.size, size(11))
        XCTAssertEqual(standardImage.size, size(14))
        XCTAssertFalse(compactImage === standardImage)
        // A changed entry forces a real pass.
        let changed = [entries[0], MenuEntry(id: "standard", title: "Plug 2", action: action, symbol: "powerplug.fill")]
        for _ in 0..<2 { renderer.update(changed, target: self) }
        XCTAssertTrue(row.subviews.compactMap { $0 as? NSImageView }.first?.image === compactImage)
        XCTAssertTrue(menu.items[1].image === standardImage)
    }

    func testStyleChangeForOneIdReplacesTheRowWithTheRightLayout() throws {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        func entries(_ style: MenuEntry.Style) -> [MenuEntry] {
            [MenuEntry(id: "row", title: "Row", action: action, style: style, symbol: "powerplug.fill")]
        }
        renderer.update(entries(.toggle), target: self)
        let regular = try XCTUnwrap(menu.items[0].view as? SwitchMenuRow)
        XCTAssertEqual(regular.rowLayout, .regular)
        renderer.update(entries(.compactToggle), target: self)
        let compact = try XCTUnwrap(menu.items[0].view as? SwitchMenuRow)
        XCTAssertEqual(compact.rowLayout, .compact)
        XCTAssertFalse(compact === regular)
        renderer.update(entries(.toggle), target: self)
        XCTAssertEqual((menu.items[0].view as? SwitchMenuRow)?.rowLayout, .regular)
        renderer.update(entries(.standard), target: self)
        XCTAssertNil(menu.items[0].view)
    }
}
