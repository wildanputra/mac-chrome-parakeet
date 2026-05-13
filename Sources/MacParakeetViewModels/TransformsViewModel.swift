import Foundation
import MacParakeetCore

/// Drives the **Transforms** tab list (ADR-022). Owns the user-visible
/// ordered set of `.transform` prompts plus the "no LLM provider" state
/// surfaced in the hero card.
///
/// Editing a single Transform happens in `TransformEditorViewModel` —
/// this VM owns the *collection*; the editor VM owns one *row's draft state*.
@MainActor
@Observable
public final class TransformsViewModel {
    public nonisolated static let historyFetchLimit = 200

    public var transforms: [Prompt] = []
    public var history: [TransformHistoryEntry] = []
    public var totalHistoryCount: Int = 0
    public var errorMessage: String?
    public var historyErrorMessage: String?

    /// Pending delete confirmation. Set when the user hits delete on a
    /// (non-built-in) Transform; cleared on confirm or cancel.
    public var pendingDeleteTransform: Prompt?
    public var pendingDeleteHistoryEntry: TransformHistoryEntry?
    public var isConfirmingClearHistory: Bool = false
    public var copiedHistoryEntryID: UUID?

    /// True when the user has at least one LLM provider configured. Drives
    /// the calm "Configure in Settings" hero state.
    public var hasLLMProvider: Bool = false

    private var repo: PromptRepositoryProtocol?
    private var historyRepo: TransformHistoryRepositoryProtocol?
    private var clipboardService: ClipboardServiceProtocol?
    private var copiedResetTask: Task<Void, Never>?

    public init() {}

    public func configure(
        repo: PromptRepositoryProtocol,
        historyRepo: TransformHistoryRepositoryProtocol? = nil,
        clipboardService: ClipboardServiceProtocol? = nil,
        hasLLMProvider: Bool
    ) {
        self.repo = repo
        self.historyRepo = historyRepo
        self.clipboardService = clipboardService
        self.hasLLMProvider = hasLLMProvider
        load()
        Task {
            await loadHistory()
        }
    }

    /// Refresh the list from the repository. Built-ins are seeded by the
    /// reconciler at launch — this view never sees an empty list under
    /// normal operation.
    public func load() {
        guard let repo else { return }
        do {
            transforms = try repo
                .fetchVisible(category: .transform)
                .sorted(by: { lhs, rhs in
                    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                })
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadHistory() async {
        guard let historyRepo else {
            history = []
            totalHistoryCount = 0
            return
        }
        do {
            let snapshot = try await Self.fetchHistorySnapshot(
                repo: historyRepo,
                limit: Self.historyFetchLimit
            )
            history = snapshot.entries
            totalHistoryCount = snapshot.totalCount
            historyErrorMessage = nil
        } catch {
            history = []
            totalHistoryCount = 0
            historyErrorMessage = error.localizedDescription
        }
    }

    public func setHasLLMProvider(_ value: Bool) {
        hasLLMProvider = value
    }

    // MARK: - Mutations

    /// Save a new or edited Transform. Wraps the underlying GRDB save and
    /// reloads the list so the UI reflects the change. Does NOT register
    /// the hotkey — the coordinator's `reloadBindings()` is invoked by the
    /// view layer after this returns successfully.
    @discardableResult
    public func save(_ prompt: Prompt) -> Bool {
        guard let repo else { return false }
        do {
            try repo.save(prompt)
            errorMessage = nil
            load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Delete a non-built-in Transform. Built-ins are protected — the
    /// underlying repository refuses them; this helper short-circuits so
    /// the UI can hide the action entirely.
    @discardableResult
    public func delete(_ prompt: Prompt) -> Bool {
        guard let repo, !prompt.isBuiltIn else { return false }
        do {
            let deleted = try repo.delete(id: prompt.id)
            if deleted {
                errorMessage = nil
                load()
            }
            return deleted
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Confirm a pending delete that was queued via `pendingDeleteTransform`.
    public func confirmPendingDelete() {
        guard let pending = pendingDeleteTransform else { return }
        pendingDeleteTransform = nil
        delete(pending)
    }

    public func confirmPendingHistoryDelete() async {
        guard let pending = pendingDeleteHistoryEntry else { return }
        pendingDeleteHistoryEntry = nil
        await deleteHistoryEntry(pending)
    }

    public func deleteHistoryEntry(_ entry: TransformHistoryEntry) async {
        guard let historyRepo else { return }
        do {
            let snapshot = try await Self.deleteHistoryEntryAndFetchSnapshot(
                repo: historyRepo,
                id: entry.id,
                limit: Self.historyFetchLimit
            )
            history = snapshot.entries
            totalHistoryCount = snapshot.totalCount
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = error.localizedDescription
        }
    }

    public func clearHistory() async {
        guard let historyRepo else { return }
        do {
            let snapshot = try await Self.clearHistoryAndFetchSnapshot(
                repo: historyRepo,
                limit: Self.historyFetchLimit
            )
            history = snapshot.entries
            totalHistoryCount = snapshot.totalCount
            isConfirmingClearHistory = false
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = error.localizedDescription
        }
    }

    public func copyOutputToClipboard(_ entry: TransformHistoryEntry) async {
        guard let clipboardService else {
            historyErrorMessage = "Clipboard service is unavailable."
            return
        }

        guard await clipboardService.copyToClipboard(entry.outputText) else {
            historyErrorMessage = "Could not copy transformed text to the clipboard."
            return
        }

        historyErrorMessage = nil
        copiedResetTask?.cancel()
        copiedHistoryEntryID = entry.id
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self.copiedHistoryEntryID = nil
        }
    }

    private static func fetchHistorySnapshot(
        repo: TransformHistoryRepositoryProtocol,
        limit: Int
    ) async throws -> (entries: [TransformHistoryEntry], totalCount: Int) {
        try await Task.detached(priority: .userInitiated) {
            let entries = try repo.fetchRecent(limit: limit)
            let totalCount = try repo.count()
            return (entries, totalCount)
        }.value
    }

    private static func deleteHistoryEntryAndFetchSnapshot(
        repo: TransformHistoryRepositoryProtocol,
        id: UUID,
        limit: Int
    ) async throws -> (entries: [TransformHistoryEntry], totalCount: Int) {
        try await Task.detached(priority: .userInitiated) {
            _ = try repo.delete(id: id)
            let entries = try repo.fetchRecent(limit: limit)
            let totalCount = try repo.count()
            return (entries, totalCount)
        }.value
    }

    private static func clearHistoryAndFetchSnapshot(
        repo: TransformHistoryRepositoryProtocol,
        limit: Int
    ) async throws -> (entries: [TransformHistoryEntry], totalCount: Int) {
        try await Task.detached(priority: .userInitiated) {
            try repo.deleteAll()
            let entries = try repo.fetchRecent(limit: limit)
            let totalCount = try repo.count()
            return (entries, totalCount)
        }.value
    }

    /// Reset a built-in Transform's content / shortcut / runningLabel back
    /// to its canonical defaults from `Prompt.builtInPrompts()`. No-op for
    /// custom Transforms (they don't have a default to revert to).
    @discardableResult
    public func resetBuiltIn(_ prompt: Prompt) -> Bool {
        guard prompt.isBuiltIn, repo != nil else { return false }
        guard let canonical = Prompt.builtInPrompts().first(where: { $0.id == prompt.id }) else {
            return false
        }
        var restored = prompt
        restored.name = canonical.name
        restored.content = canonical.content
        restored.keyboardShortcut = canonical.keyboardShortcut
        restored.runningLabel = canonical.runningLabel
        restored.sortOrder = canonical.sortOrder
        restored.updatedAt = Date()
        return save(restored)
    }

    /// Re-seed missing built-in Transforms only (does NOT overwrite user
    /// edits to existing built-ins). The header's *Reset to defaults*
    /// affordance maps to this.
    public func reseedMissingBuiltIns() {
        guard let repo else { return }
        let existingIDs = Set(transforms.map(\.id))
        let canonical = Prompt.builtInPrompts().filter { $0.category == .transform }
        for prompt in canonical where !existingIDs.contains(prompt.id) {
            do {
                try repo.save(prompt)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        load()
    }

    // MARK: - Convenience accessors

    public var customTransforms: [Prompt] {
        transforms.filter { !$0.isBuiltIn }
    }

    public var builtInTransforms: [Prompt] {
        transforms.filter(\.isBuiltIn)
    }

    /// Bindings map for the registry — `[Prompt.ID: KeyboardShortcut]`.
    /// View layer hands this to `TransformsCoordinator.reloadBindings()`
    /// after a save / delete / reseed.
    public var shortcutBindings: [UUID: KeyboardShortcut] {
        var bindings: [UUID: KeyboardShortcut] = [:]
        for transform in transforms {
            if let shortcut = transform.shortcut {
                bindings[transform.id] = shortcut
            }
        }
        return bindings
    }
}
