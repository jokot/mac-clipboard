import XCTest
import AppKit
@testable import MaClip

final class KeyShortcutsTests: XCTestCase {
    private func event(_ keyCode: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: 0, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
    }

    // MARK: - KeyCombo

    func test_comboFromArrowIgnoresTheFunctionAndKeypadFlags() {
        let combo = KeyCombo(event: event(126, "\u{F700}", [.function, .numericPad]))
        XCTAssertEqual(combo, KeyCombo(.up))
    }

    func test_comboFromCommandLetterIsLowerCase() {
        XCTAssertEqual(KeyCombo(event: event(8, "c", .command)), .command("c"))
        XCTAssertEqual(KeyCombo(event: event(1, "S", [.command, .shift])), KeyCombo(.character("s"), [.shift, .command]))
    }

    func test_comboFromSpecialKeys() {
        XCTAssertEqual(KeyCombo(event: event(36, "\r")), KeyCombo(.returnKey))
        XCTAssertEqual(KeyCombo(event: event(76, "\u{3}")), KeyCombo(.returnKey))
        XCTAssertEqual(KeyCombo(event: event(53, "\u{1B}")), KeyCombo(.escape))
        XCTAssertEqual(KeyCombo(event: event(49, " ")), KeyCombo(.space))
        XCTAssertEqual(KeyCombo(event: event(51, "\u{7F}", .command)), KeyCombo(.delete, .command))
        XCTAssertEqual(KeyCombo(event: event(116, "\u{F72C}", .function)), KeyCombo(.pageUp))
        XCTAssertEqual(KeyCombo(event: event(44, "/", .command)), .command("/"))
    }

    func test_comboDisplayUsesMacMenuOrder() {
        XCTAssertEqual(KeyCombo(.delete, [.command, .shift]).display, "\u{21E7}\u{2318}\u{232B}")
        XCTAssertEqual(KeyCombo(.character("c"), [.option, .command]).display, "\u{2325}\u{2318}C")
        XCTAssertEqual(KeyCombo(.up, .command).display, "\u{2318}\u{2191}")
        XCTAssertEqual(KeyCombo(.pageDown).display, "fn\u{2193}")
        XCTAssertEqual(KeyCombo(.escape).display, "esc")
        XCTAssertEqual(KeyCombo(.space).display, "space")
        XCTAssertEqual(KeyCombo(.returnKey, .command).display, "\u{2318}\u{21A9}")
        XCTAssertEqual(KeyCombo(.character("[")).display, "[")
    }

    // MARK: - Tables

    func test_noTableUsesOneKeyForTwoActions() {
        XCTAssertEqual(ClipKeyMap.list.conflicts, [])
        XCTAssertEqual(ClipKeyMap.preview.conflicts, [])
        XCTAssertEqual(ClipKeyMap.editing.conflicts, [])
        XCTAssertEqual(EditorKeyMap.table.conflicts, [])
        XCTAssertEqual(SettingsKeyMap.table.conflicts, [])
        XCTAssertEqual(AboutKeyMap.table.conflicts, [])
        XCTAssertEqual(PromptKeyMap.table.conflicts, [])
    }

    func test_everyListedBindingShowsInThePanel() {
        let rows = ClipKeyMap.listColumns(globalKeys: []).flatMap { $0 }.flatMap(\.rows)
        for binding in ClipKeyMap.list.bindings where binding.listed {
            XCTAssertTrue(rows.contains { $0.label == binding.label }, binding.label)
        }
    }

    func test_panelShowsTheGlobalKeys() {
        let columns = ClipKeyMap.listColumns(globalKeys: [ShortcutRow(label: "Open MaClip", keys: ["\u{2303}\u{2318}V"])])
        let groups = columns.flatMap { $0 }
        XCTAssertTrue(groups.contains { $0.title == "In any app" && $0.rows.first?.keys == ["\u{2303}\u{2318}V"] })
    }

    func test_pasteClipShowsOneRowForNineKeys() {
        let rows = ClipKeyMap.listColumns(globalKeys: []).flatMap { $0 }.flatMap(\.rows)
        XCTAssertEqual(rows.filter { $0.label == "Paste clip 1 to 9" }.map(\.keys), [["\u{2318}1\u{2013}9"]])
        XCTAssertEqual(ClipKeyMap.command(for: .command("7"), state: ClipKeyState()), .pasteClip(7))
    }

    // MARK: - Clip window: list

    private func list(_ combo: KeyCombo, _ change: (inout ClipKeyState) -> Void = { _ in }) -> ClipCommand? {
        var state = ClipKeyState()
        change(&state)
        return ClipKeyMap.command(for: combo, state: state)
    }

    func test_listKeys() {
        XCTAssertEqual(list(KeyCombo(.up)), .moveUp)
        XCTAssertEqual(list(KeyCombo(.down)), .moveDown)
        XCTAssertEqual(list(KeyCombo(.up, .command)), .moveFirst)
        XCTAssertEqual(list(KeyCombo(.end)), .moveLast)
        XCTAssertEqual(list(KeyCombo(.pageDown)), .pageDown)
        XCTAssertEqual(list(KeyCombo(.returnKey)), .paste)
        XCTAssertEqual(list(KeyCombo(.space)), .togglePreview)
        XCTAssertEqual(list(.command("c")), .copyOnly)
        XCTAssertEqual(list(.command("e")), .edit)
        XCTAssertEqual(list(.command("k")), .showActions)
        XCTAssertEqual(list(KeyCombo(.delete, .command)), .delete)
        XCTAssertEqual(list(KeyCombo(.delete, [.option, .command])), .excludeApp)
        XCTAssertEqual(list(KeyCombo(.delete, [.shift, .command])), .clearHistory)
        XCTAssertEqual(list(.command("u")), .revealConcealed)
        XCTAssertEqual(list(.command("o")), .open)
        XCTAssertEqual(list(.command("r")), .revealInFinder)
        XCTAssertEqual(list(KeyCombo(.character("c"), [.option, .command])), .copyPath)
        XCTAssertEqual(list(.command("t")), .extractText)
        XCTAssertEqual(list(.command("b")), .extractCode)
        XCTAssertEqual(list(.command(",")), .settings)
        XCTAssertEqual(list(.command("i")), .about)
        XCTAssertEqual(list(.command("w")), .closeWindow)
        XCTAssertEqual(list(.command("q")), .quit)
        XCTAssertEqual(list(.command("/")), .showShortcuts)
        XCTAssertEqual(list(.command("f")), .focusSearch)
        XCTAssertEqual(list(KeyCombo(.escape)), .back)
    }

    func test_rightArrowFocusesThePreviewOnlyWhenItIsOpen() {
        XCTAssertNil(list(KeyCombo(.right)))
        XCTAssertEqual(list(KeyCombo(.right)) { $0.previewOpen = true }, .focusPreview)
        XCTAssertNil(list(KeyCombo(.left)) { $0.previewOpen = true })
    }

    func test_plainLettersAreNotCommands() {
        XCTAssertNil(list(KeyCombo(.character("a"))))
        XCTAssertNil(list(KeyCombo(.character("e"), .shift)))
    }

    // MARK: - Clip window: search field

    private func search(_ combo: KeyCombo, text: String = "", selection: Bool = false) -> ClipCommand? {
        list(combo) {
            $0.searchFocused = true
            $0.searchText = text
            $0.textSelected = selection
            $0.previewOpen = true
        }
    }

    func test_searchFieldKeepsSpaceForTypingAfterText() {
        XCTAssertNil(search(KeyCombo(.space), text: "room"), "a search can have two words")
    }

    func test_spaceInAnEmptySearchFieldOpensThePreview() {
        XCTAssertEqual(search(KeyCombo(.space)), .togglePreview)
    }

    func test_spaceAfterTheArrowsOpensThePreview() {
        // ↑ ↓ take the cursor out of the search field. The search text stays.
        XCTAssertTrue(ClipKeyMap.leavesSearchField(.moveDown))
        XCTAssertTrue(ClipKeyMap.leavesSearchField(.moveFirst))
        XCTAssertTrue(ClipKeyMap.leavesSearchField(.pageDown))
        XCTAssertFalse(ClipKeyMap.leavesSearchField(.paste))
        XCTAssertEqual(list(KeyCombo(.space)) { $0.searchText = "inv" }, .togglePreview)
    }

    func test_deleteInTheListEditsTheSearch() {
        XCTAssertEqual(list(KeyCombo(.delete)) { $0.searchText = "inv" }, .deleteSearchLetter)
        XCTAssertNil(list(KeyCombo(.delete)), "no search text, nothing to delete")
        XCTAssertNil(search(KeyCombo(.delete), text: "inv"), "the search field deletes the letter itself")
    }

    func test_searchFieldStillMovesAndPastes() {
        XCTAssertEqual(search(KeyCombo(.down), text: "inv"), .moveDown)
        XCTAssertEqual(search(KeyCombo(.returnKey), text: "inv"), .paste)
        XCTAssertEqual(search(KeyCombo(.escape), text: "inv"), .back)
    }

    func test_searchFieldArrowsSwitchSidesOnlyWhenEmpty() {
        XCTAssertEqual(search(KeyCombo(.right)), .focusPreview)
        XCTAssertNil(search(KeyCombo(.right), text: "inv"))
        XCTAssertNil(search(KeyCombo(.left), text: "inv"))
    }

    func test_searchFieldKeepsTextKeys() {
        XCTAssertNil(search(KeyCombo(.delete, .command), text: "inv"), "⌘⌫ deletes the search text")
        XCTAssertEqual(search(KeyCombo(.delete, .command)), .delete, "an empty field has nothing to delete")
        XCTAssertNil(search(.command("c"), text: "inv", selection: true), "⌘C copies the selected text")
        XCTAssertEqual(search(.command("c"), text: "inv"), .copyOnly)
    }

    // MARK: - Clip window: preview

    private func preview(_ combo: KeyCombo, selection: Bool = false) -> ClipCommand? {
        list(combo) {
            $0.previewOpen = true
            $0.pane = .preview
            $0.textSelected = selection
        }
    }

    func test_previewKeys() {
        XCTAssertEqual(preview(KeyCombo(.down)), .scrollDown)
        XCTAssertEqual(preview(KeyCombo(.up)), .scrollUp)
        XCTAssertEqual(preview(KeyCombo(.pageDown)), .scrollPageDown)
        XCTAssertEqual(preview(KeyCombo(.down, .command)), .scrollBottom)
        XCTAssertEqual(preview(KeyCombo(.left)), .focusList)
        XCTAssertEqual(preview(KeyCombo(.space)), .togglePreview)
        XCTAssertEqual(preview(KeyCombo(.escape)), .back)
        XCTAssertNil(preview(KeyCombo(.right)))
    }

    func test_previewRunsTheClipKeys() {
        XCTAssertEqual(preview(KeyCombo(.returnKey)), .paste)
        XCTAssertEqual(preview(.command("e")), .edit)
        XCTAssertEqual(preview(KeyCombo(.delete, .command)), .delete)
        XCTAssertEqual(preview(.command("/")), .showShortcuts)
        XCTAssertNil(preview(.command("c"), selection: true), "⌘C copies the selected preview text")
    }

    // MARK: - Clip window: edit mode and the panel

    func test_editModeKeepsTextKeys() {
        let editing: (inout ClipKeyState) -> Void = { $0.previewOpen = true; $0.pane = .preview; $0.editing = true }
        XCTAssertEqual(list(KeyCombo(.escape), editing), .cancelEdit)
        XCTAssertEqual(list(KeyCombo(.returnKey, .command), editing), .saveEdit)
        XCTAssertEqual(list(.command("s"), editing), .saveEdit)
        XCTAssertEqual(list(.command("/"), editing), .showShortcuts)
        XCTAssertNil(list(KeyCombo(.left), editing))
        XCTAssertNil(list(KeyCombo(.delete, .command), editing))
        XCTAssertNil(list(KeyCombo(.returnKey), editing))
    }

    func test_openPanelTakesEveryKey() {
        let panel: (inout ClipKeyState) -> Void = { $0.shortcutsVisible = true }
        XCTAssertEqual(list(KeyCombo(.escape), panel), .showShortcuts)
        XCTAssertEqual(list(.command("/"), panel), .showShortcuts)
        XCTAssertEqual(list(.command("q"), panel), .quit)
        XCTAssertEqual(list(KeyCombo(.down), panel), .ignore)
        XCTAssertEqual(list(KeyCombo(.character("a")), panel), .ignore)
    }

    // MARK: - Other windows

    func test_editorKeys() {
        XCTAssertEqual(EditorKeyMap.table.command(for: KeyCombo(.character("c"))), .tool(.crop))
        XCTAssertEqual(EditorKeyMap.table.command(for: KeyCombo(.character("x"))), .tool(.redact))
        XCTAssertEqual(EditorKeyMap.table.command(for: KeyCombo(.character("3"))), .color(3))
        XCTAssertEqual(EditorKeyMap.table.command(for: KeyCombo(.character("]"))), .thicker)
        XCTAssertEqual(EditorKeyMap.table.command(for: .command("l")), .rotateLeft)
        XCTAssertEqual(EditorKeyMap.table.command(for: KeyCombo(.character("s"), [.shift, .command])), .saveAsNew)
        XCTAssertEqual(EditorKeyMap.table.command(for: KeyCombo(.returnKey)), .save)
        XCTAssertEqual(EditorKeyMap.table.command(for: .command("w")), .cancel)
    }

    func test_everyToolHasAKey() {
        for tool in EditTool.allCases {
            XCTAssertTrue(EditorKeyMap.table.bindings.contains { $0.command == .tool(tool) }, tool.rawValue)
        }
    }

    func test_settingsKeys() {
        XCTAssertEqual(SettingsKeyMap.table.command(for: .command("1")), .tab(.general))
        XCTAssertEqual(SettingsKeyMap.table.command(for: .command("2")), .tab(.appearance))
        XCTAssertEqual(SettingsKeyMap.table.command(for: .command("4")), .tab(.storage))
        XCTAssertEqual(SettingsKeyMap.table.command(for: .command("5")), .tab(.privacy))
        XCTAssertEqual(SettingsKeyMap.table.command(for: .command("w")), .close)
        XCTAssertEqual(SettingsKeyMap.table.command(for: KeyCombo(.delete)), .removeSelectedApp)
    }

    func test_settingsControlKeysWorkWithoutTheMacKeyboardNavigationSetting() {
        let table = SettingsKeyMap.table
        XCTAssertEqual(table.command(for: KeyCombo(.tab)), .nextControl)
        XCTAssertEqual(table.command(for: KeyCombo(.down)), .nextControl)
        XCTAssertEqual(table.command(for: KeyCombo(.tab, .shift)), .previousControl)
        XCTAssertEqual(table.command(for: KeyCombo(.up)), .previousControl)
        XCTAssertEqual(table.command(for: KeyCombo(.space)), .activate)
        XCTAssertEqual(table.command(for: KeyCombo(.returnKey)), .activate)
        XCTAssertEqual(table.command(for: KeyCombo(.left)), .stepBack)
        XCTAssertEqual(table.command(for: KeyCombo(.right)), .stepForward)
    }

    func test_numberFieldKeepsTypingKeys() {
        XCTAssertTrue(SettingsKeyMap.worksInTextField(KeyCombo(.tab)))
        XCTAssertTrue(SettingsKeyMap.worksInTextField(KeyCombo(.tab, .shift)))
        XCTAssertTrue(SettingsKeyMap.worksInTextField(.command("2")))
        XCTAssertFalse(SettingsKeyMap.worksInTextField(KeyCombo(.space)))
        XCTAssertFalse(SettingsKeyMap.worksInTextField(KeyCombo(.left)))
        XCTAssertFalse(SettingsKeyMap.worksInTextField(KeyCombo(.delete)))
        XCTAssertFalse(SettingsKeyMap.worksInTextField(KeyCombo(.returnKey)), "↩ in the field applies the number")
        // A one-line field does nothing with ↑ ↓, so they move the focus, as in the rest of Settings.
        XCTAssertTrue(SettingsKeyMap.worksInTextField(KeyCombo(.down)))
        XCTAssertTrue(SettingsKeyMap.worksInTextField(KeyCombo(.up)))
    }

    func test_settingsFocusMovesInOrderAndWraps() {
        let ids = ["theme", "paste", "top"]
        XCTAssertEqual(SettingsFocus.move(in: ids, from: nil, by: 1), "theme")
        XCTAssertEqual(SettingsFocus.move(in: ids, from: nil, by: -1), "top")
        XCTAssertEqual(SettingsFocus.move(in: ids, from: "theme", by: 1), "paste")
        XCTAssertEqual(SettingsFocus.move(in: ids, from: "top", by: 1), "theme")
        XCTAssertEqual(SettingsFocus.move(in: ids, from: "theme", by: -1), "top")
        XCTAssertEqual(SettingsFocus.move(in: ids, from: "gone", by: 1), "theme", "a control that is gone starts again at the top")
        XCTAssertNil(SettingsFocus.move(in: [], from: nil, by: 1))
    }

    func test_choiceStepsStopAtTheEnds() {
        let values = [5, 10, 20]
        XCTAssertEqual(SettingsFocus.step(values, from: 10, by: 1), 20)
        XCTAssertEqual(SettingsFocus.step(values, from: 20, by: 1), 20)
        XCTAssertEqual(SettingsFocus.step(values, from: 5, by: -1), 5)
        XCTAssertEqual(SettingsFocus.step(values, from: 7, by: 1), 5, "a value not in the list goes to the first")
    }

    func test_removingTheFocusedAppFocusesTheNextApp() {
        let ids = ["app:a", "app:b", "app:c", "add"]
        XCTAssertEqual(SettingsFocus.afterRemoving("app:b", from: ids), "app:c")
        XCTAssertEqual(SettingsFocus.afterRemoving("app:c", from: ids), "app:b")
        XCTAssertEqual(SettingsFocus.afterRemoving("app:a", from: ["app:a", "add"]), "add")
    }

    func test_tableGroupsKeepTheirOrder() {
        let titles = SettingsKeyMap.table.groups().map(\.title)
        XCTAssertEqual(titles, ["Tabs", "Controls", "Window"])
    }
}

final class KeyMonitorBlockTests: XCTestCase {
    private final class Owner {}

    private let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, characters: "a",
                                       charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!

    func test_aKeyThatTheHandlerUsesIsNotSentOnAgain() {
        let owner = Owner()
        let block = KeyMonitorBlock.make(owner) { _, _ in nil }
        XCTAssertNil(block(key), "macOS plays the error sound for a used key that it gets back")
    }

    func test_aKeyThatTheHandlerDoesNotUseGoesOn() {
        let owner = Owner()
        let block = KeyMonitorBlock.make(owner) { _, event in event }
        XCTAssertTrue(block(key) === key)
    }

    func test_aKeyGoesOnAfterTheOwnerIsGone() {
        var owner: Owner? = Owner()
        let block = KeyMonitorBlock.make(owner!) { _, _ in nil }
        owner = nil
        XCTAssertTrue(block(key) === key)
    }
}
