import XCTest
@testable import MacParakeetCore
@testable import MacParakeetViewModels

@MainActor
final class TransformsViewModelTests: XCTestCase {
    var manager: DatabaseManager!
    var repo: PromptRepository!
    var viewModel: TransformsViewModel!

    override func setUp() async throws {
        manager = try DatabaseManager()
        repo = PromptRepository(dbQueue: manager.dbQueue)
        viewModel = TransformsViewModel()
        viewModel.configure(repo: repo, hasLLMProvider: true)
    }

    func testLoadPullsOnlyTransformCategoryPrompts() {
        XCTAssertEqual(viewModel.transforms.count, 3, "Three built-in Transforms ship with the app.")
        XCTAssertTrue(viewModel.transforms.allSatisfy { $0.category == .transform })
        // Built-in count is exposed via the helper.
        XCTAssertEqual(viewModel.builtInTransforms.count, 3)
        XCTAssertEqual(viewModel.customTransforms.count, 0)
    }

    func testLoadOrdersBySortOrder() {
        let names = viewModel.transforms.map(\.name)
        XCTAssertEqual(names, ["Polish", "Distill", "Decide"])
    }

    func testShortcutBindingsExposesNonNilShortcuts() {
        let bindings = viewModel.shortcutBindings
        XCTAssertEqual(bindings.count, 3, "All three built-ins ship with default shortcuts.")
        let labels = Set(bindings.values.map(\.keyLabel))
        XCTAssertEqual(labels, ["1", "2", "3"])
    }

    func testSaveNewCustomTransformAppendsToList() {
        let prompt = Prompt(
            id: UUID(),
            name: "Soften",
            content: "Make the message warmer.",
            category: .transform,
            isBuiltIn: false,
            sortOrder: 200,
            keyboardShortcut: nil,
            runningLabel: nil
        )
        XCTAssertTrue(viewModel.save(prompt))
        XCTAssertEqual(viewModel.transforms.count, 4)
        XCTAssertTrue(viewModel.customTransforms.contains(where: { $0.name == "Soften" }))
    }

    func testDeleteCustomTransformRemovesRow() {
        let prompt = Prompt(
            id: UUID(),
            name: "Sharpen",
            content: "Make it crisper.",
            category: .transform,
            isBuiltIn: false,
            sortOrder: 201
        )
        viewModel.save(prompt)
        XCTAssertEqual(viewModel.transforms.count, 4)

        XCTAssertTrue(viewModel.delete(prompt))
        XCTAssertEqual(viewModel.transforms.count, 3)
        XCTAssertFalse(viewModel.transforms.contains(where: { $0.id == prompt.id }))
    }

    func testDeleteBuiltInIsRejected() {
        let polish = viewModel.transforms.first(where: { $0.name == "Polish" })!
        XCTAssertFalse(viewModel.delete(polish), "Built-ins must be protected from deletion.")
        XCTAssertEqual(viewModel.transforms.count, 3)
    }

    func testConfirmPendingDeleteClearsAndDeletes() {
        let prompt = Prompt(
            id: UUID(),
            name: "Temp",
            content: "Body.",
            category: .transform,
            isBuiltIn: false
        )
        viewModel.save(prompt)
        viewModel.pendingDeleteTransform = prompt

        viewModel.confirmPendingDelete()

        XCTAssertNil(viewModel.pendingDeleteTransform)
        XCTAssertFalse(viewModel.transforms.contains(where: { $0.id == prompt.id }))
    }

    func testResetBuiltInRestoresDefaultContent() {
        // User customizes Polish: prompt body + shortcut + label.
        var polish = viewModel.transforms.first(where: { $0.name == "Polish" })!
        let customized = polish
        polish.content = "Custom polish prompt body."
        polish.keyboardShortcut = KeyboardShortcut(
            modifiers: KeyboardShortcut.ModifierFlag.option.rawValue
                | KeyboardShortcut.ModifierFlag.shift.rawValue,
            keyCode: 0x23,
            keyLabel: "P"
        ).encodedString()
        polish.runningLabel = "Refining…"
        viewModel.save(polish)

        XCTAssertTrue(viewModel.resetBuiltIn(polish))

        let restored = viewModel.transforms.first(where: { $0.id == customized.id })!
        XCTAssertNotEqual(restored.content, "Custom polish prompt body.")
        XCTAssertEqual(restored.shortcut?.keyLabel, "1", "Default shortcut should be restored.")
        XCTAssertEqual(restored.runningLabel, "Polishing…", "Default running label should be restored.")
    }

    func testReseedMissingBuiltInsRecreatesDeletedDefault() throws {
        // Force-delete Polish via raw SQL (bypassing the built-in protection)
        // to simulate a corrupted state where a built-in is missing.
        let polish = viewModel.transforms.first(where: { $0.name == "Polish" })!
        try manager.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM prompts WHERE id = ?", arguments: [polish.id])
        }
        viewModel.load()
        XCTAssertEqual(viewModel.transforms.count, 2, "Polish should be gone before reseed.")

        viewModel.reseedMissingBuiltIns()

        XCTAssertEqual(viewModel.transforms.count, 3)
        XCTAssertTrue(viewModel.transforms.contains(where: { $0.name == "Polish" }))
    }

    func testReseedDoesNotOverwriteExistingBuiltIn() {
        // Customize Polish, then reseed — the custom values must survive.
        var polish = viewModel.transforms.first(where: { $0.name == "Polish" })!
        let customContent = "User-customized Polish body."
        polish.content = customContent
        viewModel.save(polish)

        viewModel.reseedMissingBuiltIns()

        let reloaded = viewModel.transforms.first(where: { $0.name == "Polish" })!
        XCTAssertEqual(reloaded.content, customContent, "Reseed must not overwrite existing built-in customizations.")
    }
}
