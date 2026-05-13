import XCTest
@testable import MacParakeetCore
@testable import MacParakeetViewModels

@MainActor
final class PromptsViewModelTests: XCTestCase {
    var viewModel: PromptsViewModel!
    var repo: MockPromptRepository!

    override func setUp() {
        viewModel = PromptsViewModel()
        repo = MockPromptRepository()
        repo.prompts = Prompt.builtInPrompts()
        viewModel.configure(repo: repo)
    }

    func testLoadPromptsFiltersOutTransformCategory() {
        XCTAssertEqual(viewModel.prompts.count, 6)
        XCTAssertTrue(viewModel.prompts.allSatisfy { $0.category == .result })
        XCTAssertFalse(viewModel.prompts.contains(where: { $0.name == "Polish" }))
    }

    func testAddPromptCreatesCustomSummaryPrompt() {
        viewModel.newName = "Standup Notes"
        viewModel.newContent = "Summarize as a daily standup."

        viewModel.addPrompt()

        // 6 `.result` built-ins + 1 custom. Transform built-ins live in the
        // same table but are intentionally not part of the summary library.
        XCTAssertEqual(viewModel.prompts.count, 7)
        XCTAssertTrue(viewModel.prompts.contains(where: { $0.name == "Standup Notes" && !$0.isBuiltIn }))
    }

    func testAddPromptRejectsDuplicateNameCaseInsensitive() {
        viewModel.newName = "summary"
        viewModel.newContent = "Duplicate"

        viewModel.addPrompt()

        // Rejected; the 6 summary built-ins remain (no add).
        XCTAssertEqual(viewModel.prompts.count, 6)
        XCTAssertEqual(viewModel.errorMessage, "'summary' already exists")
    }

    func testAddPromptRejectsDuplicateTransformNameHiddenFromLibrary() {
        viewModel.newName = "Polish"
        viewModel.newContent = "Duplicate transform name"

        viewModel.addPrompt()

        XCTAssertEqual(viewModel.prompts.count, 6)
        XCTAssertEqual(viewModel.errorMessage, "'Polish' already exists")
    }

    func testUpdatePromptRejectsDuplicateTransformNameHiddenFromLibrary() {
        let custom = Prompt(name: "Old", content: "Old content", isBuiltIn: false, sortOrder: 99)
        repo.prompts.append(custom)
        viewModel.loadPrompts()

        viewModel.updatePrompt(custom, name: "Polish", content: "New content")

        let unchanged = repo.prompts.first(where: { $0.id == custom.id })
        XCTAssertEqual(unchanged?.name, "Old")
        XCTAssertEqual(viewModel.errorMessage, "'Polish' already exists")
    }

    func testAddPromptValidationClearsWhenFieldsChange() {
        viewModel.addPrompt()
        XCTAssertEqual(viewModel.errorMessage, "Prompt name and content are required.")

        viewModel.newName = "Hello"
        XCTAssertNil(viewModel.errorMessage)

        viewModel.addPrompt()
        XCTAssertEqual(viewModel.errorMessage, "Prompt name and content are required.")

        viewModel.newContent = "Prompt content"
        XCTAssertNil(viewModel.errorMessage)
    }

    func testToggleVisibilityChangesPromptState() {
        let prompt = viewModel.prompts.first { $0.name == "Chapter Breakdown" }!

        viewModel.toggleVisibility(prompt)

        XCTAssertFalse(viewModel.prompts.first(where: { $0.id == prompt.id })?.isVisible ?? true)
    }

    func testRestoreDefaultsShowsAllBuiltIns() {
        let prompt = viewModel.prompts.first { $0.name == "Chapter Breakdown" }!
        viewModel.toggleVisibility(prompt)
        XCTAssertFalse(viewModel.prompts.first(where: { $0.id == prompt.id })?.isVisible ?? true)

        viewModel.restoreDefaults()

        XCTAssertTrue(viewModel.prompts.filter(\.isBuiltIn).allSatisfy(\.isVisible))
    }

    func testUpdatePromptPersistsChanges() {
        let custom = Prompt(name: "Old", content: "Old content", isBuiltIn: false, sortOrder: 99)
        repo.prompts.append(custom)
        viewModel.loadPrompts()

        viewModel.updatePrompt(custom, name: "New", content: "New content")

        let updated = viewModel.prompts.first(where: { $0.id == custom.id })
        XCTAssertEqual(updated?.name, "New")
        XCTAssertEqual(updated?.content, "New content")
    }
}
