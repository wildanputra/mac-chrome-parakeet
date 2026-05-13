import Foundation
import MacParakeetCore
import MacParakeetViewModels

/// Adapter that lets the editor sheet's ViewModel layer call into the
/// GUI's `TransformsHotkeyCollisionChecker` without importing it
/// (MacParakeetViewModels can't depend on MacParakeet — only the other
/// way around). The protocol mirror is defined in
/// `TransformEditorViewModel.swift`; this file is the binding.
extension TransformsHotkeyCollisionChecker: TransformShortcutCollisionChecking {
    public func checkForEditor(
        candidate: KeyboardShortcut,
        existing: [UUID: KeyboardShortcut],
        excludingPromptID: UUID?,
        dictationHotkeys: [HotkeyTrigger],
        meetingHotkey: HotkeyTrigger?
    ) -> TransformShortcutCollision? {
        let result: TransformsHotkeyCollision? = self.check(
            candidate: candidate,
            existing: existing,
            excludingPromptID: excludingPromptID,
            dictationHotkeys: dictationHotkeys,
            meetingHotkey: meetingHotkey
        )
        switch result {
        case nil: return nil
        case .missingModifier: return .missingModifier
        case .macOSDeadKey: return .macOSDeadKey
        case .duplicateTransform(let id): return .duplicateTransform(otherPromptID: id)
        case .dictationHotkey: return .dictationHotkey
        case .meetingHotkey: return .meetingHotkey
        }
    }
}
