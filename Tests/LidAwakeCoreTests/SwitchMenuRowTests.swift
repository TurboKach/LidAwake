import AppKit
import XCTest
@testable import LidAwakeCore

final class SwitchMenuRowTests: XCTestCase {
    private final class Target: NSObject {
        var change: () -> Void = {}
        @objc func toggle() { change() }
    }

    private func entry(on: Bool, enabled: Bool = true) -> MenuEntry {
        MenuEntry(id: "enabled", title: "LidAwake", action: #selector(Target.toggle), keyEquivalent: "e",
                  state: on ? .on : .off, enabled: enabled, style: .toggle,
                  subtitle: "Staying awake · AC power", symbol: "cup.and.saucer.fill")
    }

    func testNativeSwitchHasAccessibleLabelAndStaysStableAcrossPolls() throws {
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([entry(on: true)], target: target)
        let item = try XCTUnwrap(menu.items.first)
        let row = try XCTUnwrap(item.view as? SwitchMenuRow)
        let statusIcon = try XCTUnwrap(row.subviews.compactMap { $0 as? NSImageView }.first)
        let originalImage = try XCTUnwrap(statusIcon.image)
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertEqual(row.toggle.accessibilityLabel(), "LidAwake")
        let frame = row.frame
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didChangeItemNotification,
                                                              object: menu, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        for _ in 0..<5 { renderer.update([entry(on: true)], target: target) }
        XCTAssertTrue(item.view === row)
        XCTAssertEqual(row.frame, frame)
        XCTAssertEqual(notifications, 0)
        XCTAssertTrue(statusIcon.image === originalImage)
    }

    func testClickKeepsRequestedPositionDuringWorkAndRollsBackOnFailure() throws {
        _ = NSApplication.shared
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([entry(on: true)], target: target)
        let row = try XCTUnwrap(menu.items.first?.view as? SwitchMenuRow)
        var calls = 0
        target.change = {
            calls += 1
            renderer.update([self.entry(on: true, enabled: false)], target: target)
        }
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(row.toggle.state, .off)
        XCTAssertFalse(row.toggle.isEnabled)
        renderer.update([entry(on: true)], target: target)
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertTrue(row.toggle.isEnabled)
        // Canceling setup may return without starting a background operation.
        target.change = { calls += 1 }
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(row.toggle.state, .on)
    }

    func testKeyboardEquivalentAndDisabledStateUseTheSameMenuAction() throws {
        _ = NSApplication.shared
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([entry(on: true, enabled: false)], target: target)
        let row = try XCTUnwrap(menu.items.first?.view as? SwitchMenuRow)
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertFalse(row.toggle.isEnabled)
        var calls = 0
        target.change = { calls += 1 }
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 0)
        renderer.update([entry(on: true)], target: target)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                 timestamp: 0, windowNumber: 0, context: nil,
                                                 characters: "e", charactersIgnoringModifiers: "e",
                                                 isARepeat: false, keyCode: 14))
        XCTAssertTrue(menu.performKeyEquivalent(with: event))
        XCTAssertEqual(calls, 1)
    }

    // MARK: Compact layout

    private func compactEntry(id: String = "ac", title: String = "Connected to Power", on: Bool, enabled: Bool = true,
                              symbol: String? = "powerplug.fill", indentationLevel: Int = 1) -> MenuEntry {
        MenuEntry(id: id, title: title, action: #selector(Target.toggle), state: on ? .on : .off, enabled: enabled,
                  indentationLevel: indentationLevel, style: .compactToggle, symbol: symbol)
    }

    private func compactRow(_ menu: NSMenu, at index: Int = 0) throws -> SwitchMenuRow {
        let row = try XCTUnwrap(menu.items[index].view as? SwitchMenuRow)
        XCTAssertEqual(row.rowLayout, .compact)
        return row
    }

    private func subviews(of row: SwitchMenuRow) throws -> (label: NSTextField, icon: NSImageView) {
        (try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first),
         try XCTUnwrap(row.subviews.compactMap { $0 as? NSImageView }.first))
    }

    private func layOut(_ row: SwitchMenuRow, width: CGFloat? = nil) {
        if let width = width { row.setFrameSize(NSSize(width: width, height: row.frame.height)) }
        row.needsLayout = true
        row.layoutSubtreeIfNeeded()
    }

    func testCompactEntryGetsACompactRowWithoutMenuImage() throws {
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([compactEntry(on: true)], target: target)
        let row = try compactRow(menu)
        XCTAssertNil(menu.items[0].image)
        XCTAssertEqual(row.toggle.controlSize, .small)
        XCTAssertEqual(row.toggle.accessibilityLabel(), "Connected to Power")
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertTrue(row.toggle.isEnabled)
        XCTAssertEqual(row.frame.height, 24)
        XCTAssertEqual(row.subviews.compactMap { $0 as? NSImageView }.count, 1)
        renderer.update([compactEntry(on: false, enabled: false)], target: target)
        XCTAssertEqual(row.toggle.state, .off)
        XCTAssertFalse(row.toggle.isEnabled)
    }

    func testCompactRowStaysStableAcrossPolls() throws {
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([compactEntry(on: true)], target: target)
        let item = menu.items[0]
        let row = try compactRow(menu)
        let (_, icon) = try subviews(of: row)
        let image = try XCTUnwrap(icon.image)
        let frame = row.frame
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didChangeItemNotification,
                                                              object: menu, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        for _ in 0..<5 { renderer.update([compactEntry(on: true)], target: target) }
        XCTAssertTrue(item.view === row)
        XCTAssertEqual(row.frame, frame)
        XCTAssertEqual(notifications, 0)
        XCTAssertTrue(icon.image === image)
    }

    func testCompactClickKeepsRequestedPositionAndRollsBackOrConfirms() throws {
        _ = NSApplication.shared
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([compactEntry(on: true)], target: target)
        let row = try compactRow(menu)
        var calls = 0
        target.change = {
            calls += 1
            renderer.update([self.compactEntry(on: true, enabled: false)], target: target)
        }
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(row.toggle.state, .off)
        XCTAssertFalse(row.toggle.isEnabled)
        // The state did not change: roll back.
        renderer.update([compactEntry(on: true)], target: target)
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertTrue(row.toggle.isEnabled)
        // The state changed: confirm.
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 2)
        renderer.update([compactEntry(on: false)], target: target)
        XCTAssertEqual(row.toggle.state, .off)
        XCTAssertEqual(calls, 2)
    }

    func testDisabledCompactRowSendsNoAction() throws {
        _ = NSApplication.shared
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([compactEntry(on: true, enabled: false)], target: target)
        let row = try compactRow(menu)
        var calls = 0
        target.change = { calls += 1 }
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(row.toggle.state, .on)
    }

    func testCompactRowThatStaysDisabledAfterItsClickShowsTheLaterEnabledState() throws {
        _ = NSApplication.shared
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([compactEntry(on: true)], target: target)
        let row = try compactRow(menu)
        // The last condition turned off: the row is disabled with state off.
        target.change = { renderer.update([self.compactEntry(on: false, enabled: false)], target: target) }
        row.toggle.performClick(nil)
        XCTAssertEqual(row.toggle.state, .off)
        XCTAssertFalse(row.toggle.isEnabled)
        renderer.update([compactEntry(on: true)], target: target)
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertTrue(row.toggle.isEnabled)
    }

    func testCompactTitleNeverRunsUnderTheSwitch() throws {
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        let titles = ["При питании от батареи", "A considerably longer synthetic condition title that is not translated anywhere"]
        renderer.update(titles.enumerated().map { compactEntry(id: "row\($0.offset)", title: $0.element, on: true) },
                        target: target)
        for index in 0..<titles.count {
            let row = try compactRow(menu, at: index)
            let (label, _) = try subviews(of: row)
            let textWidth = ceil((titles[index] as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width)
            XCTAssertEqual(row.frame.height, 24)
            // Natural width, and a menu that stretched the row wider.
            let natural = row.frame.width
            for width in [natural, natural + 80] {
                layOut(row, width: width)
                XCTAssertGreaterThanOrEqual(label.frame.width, textWidth)
                XCTAssertGreaterThanOrEqual(row.toggle.frame.minX - label.frame.maxX, 16)
                XCTAssertGreaterThanOrEqual(row.frame.width, label.frame.maxX + 16 + row.toggle.frame.width)
            }
            // Last resort: a row narrower than it needs truncates the title instead of running under the switch.
            layOut(row, width: natural - 60)
            XCTAssertGreaterThanOrEqual(row.toggle.frame.minX - label.frame.maxX, 16)
        }
    }

    /// The x (points) of the first column with ink, on a 2x bitmap; nil if nothing is drawn.
    private func firstInkColumn(in size: NSSize, draw: (NSRect) -> Void) -> CGFloat? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { return CGFloat(x) / 2 }
        }
        return nil
    }

    private func firstInkColumn(of label: NSTextField) -> CGFloat? {
        firstInkColumn(in: label.frame.size) { bounds in label.cell?.draw(withFrame: bounds, in: label) }
    }

    private func firstInkColumn(ofPlain title: String, font: NSFont) -> CGFloat? {
        firstInkColumn(in: NSSize(width: 600, height: 24)) { _ in (title as NSString).draw(at: .zero, withAttributes: [.font: font]) }
    }

    func testCompactTitleIsDrawnWholeAtTheDesignPosition() throws {
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        let titles = ["Connected to Power", "On Battery", "При питании от сети", "При питании от батареи",
                      "A considerably longer synthetic condition title that is not translated anywhere"]
        renderer.update(titles.enumerated().map { compactEntry(id: "row\($0.offset)", title: $0.element, on: true) },
                        target: target)
        for (index, title) in titles.enumerated() {
            let row = try compactRow(menu, at: index)
            let (label, _) = try subviews(of: row)
            let cell = try XCTUnwrap(label.cell)
            for width in [row.frame.width, row.frame.width + 80] {
                layOut(row, width: width)
                // The cell needs this much to draw the whole string; the frame must offer it.
                XCTAssertGreaterThanOrEqual(label.frame.width, ceil(cell.cellSize.width), title)
                XCTAssertGreaterThanOrEqual(row.toggle.frame.minX - label.frame.maxX, 16, title)
                // The ink starts where the same string drawn plainly at the design x would start.
                let designX: CGFloat = 24 + 12 + 19 + 6.5
                let drawn = try XCTUnwrap(firstInkColumn(of: label)) + label.frame.minX
                let plain = try XCTUnwrap(firstInkColumn(ofPlain: title, font: try XCTUnwrap(label.font))) + designX
                XCTAssertEqual(drawn, plain, accuracy: 0.5, title)
            }
        }
    }

    func testCompactInsetFollowsTheStateColumnOfTheMenu() throws {
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        func entries(_ state: NSControl.StateValue) -> [MenuEntry] {
            [MenuEntry(id: "other", title: "Other", action: #selector(Target.toggle), state: state),
             MenuEntry(id: "ac", title: "Connected to Power", action: #selector(Target.toggle), indentationLevel: 0,
                       style: .compactToggle)]
        }
        // A row created in a pass gets that pass's value.
        renderer.update(entries(.on), target: target)
        let row = try compactRow(menu, at: 1)
        let (label, _) = try subviews(of: row)
        layOut(row)
        XCTAssertEqual(label.frame.minX, 24)
        renderer.update(entries(.off), target: target)
        layOut(row)
        XCTAssertEqual(label.frame.minX, 16)
        renderer.update(entries(.mixed), target: target)
        layOut(row)
        XCTAssertEqual(label.frame.minX, 24)
        // A fresh menu without any state starts at 16.
        let other = NSMenu()
        other.autoenablesItems = false
        let fresh = StableMenu(menu: other)
        fresh.update(entries(.off), target: target)
        let freshRow = try compactRow(other, at: 1)
        layOut(freshRow)
        XCTAssertEqual(try subviews(of: freshRow).label.frame.minX, 16)
    }
}
