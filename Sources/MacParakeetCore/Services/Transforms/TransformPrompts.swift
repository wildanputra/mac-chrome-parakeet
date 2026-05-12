import Foundation

/// Hardcoded prompts used by the Transforms spike. Phase 2 replaces this with
/// `Prompt` rows in the database (category `.transform`) — see
/// `docs/research/transforms-design-2026-05.md` §3.
public enum TransformSpikePrompts {
    /// Default Polish prompt for the AX-coverage spike. Intentionally simple
    /// and tone-preserving to give the smoke matrix a clean signal —
    /// rule-toggle composition (WisprFlow's `Make more concise` etc.) is a
    /// Phase 3 polish item, not a spike concern.
    public static let polish: String = """
    Polish the following text to sound clearer in the original author's voice. \
    Preserve meaning and tone. Fix filler words, awkward phrasing, and grammar. \
    Don't add new content or change the message. Return only the polished text, \
    no explanation.
    """
}
