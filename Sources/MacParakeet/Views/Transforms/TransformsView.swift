import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

/// The **Transforms** tab — top-level sidebar destination (ADR-022).
///
/// Layout: hero strip → My Transforms grid (3-up cards + Create-your-own
/// tile) → footer with reseed-missing affordance. Calmer no-provider
/// banner replaces the hero when no LLM is configured.
///
/// Visual continuity: rounded display type (no serif — we use
/// `.rounded` system font, not a literal serif copy of the reference
/// screenshots), warm coral accent only on the keycap badges + primary
/// CTAs, generous whitespace, hover lift on cards via the existing
/// `cardRest`/`cardHover` shadow tokens.
struct TransformsView: View {
    @Bindable var viewModel: TransformsViewModel
    let llmConfiguredAction: () -> Void
    let onEdit: (Prompt) -> Void
    let onCreate: () -> Void
    let onBindingsChanged: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                heroHeader

                if viewModel.hasLLMProvider {
                    heroExplainer
                } else {
                    noProviderBanner
                }

                myTransformsHeader
                transformGrid

                footerActions
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignSystem.Colors.background)
        .alert(
            "Delete this Transform?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteTransform != nil },
                set: { if !$0 { viewModel.pendingDeleteTransform = nil } }
            ),
            presenting: viewModel.pendingDeleteTransform
        ) { transform in
            Button("Delete", role: .destructive) {
                viewModel.confirmPendingDelete()
                onBindingsChanged()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteTransform = nil
            }
        } message: { transform in
            Text("“\(transform.name)” will be removed. You can re-create it later.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Transforms")
                .font(DesignSystem.Typography.heroTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Press a hotkey on any selected text to rewrite it through your LLM provider — in Slack, Notes, Gmail, your editor, anywhere on Mac.")
                .font(DesignSystem.Typography.bodyLarge)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(maxWidth: 640, alignment: .leading)
        }
        .padding(.top, DesignSystem.Spacing.md)
    }

    @ViewBuilder
    private var heroExplainer: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Label("Highlight any text on your Mac.", systemImage: "1.circle.fill")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Label("Press a Transform's hotkey (⌥1, ⌥2, ⌥3, …).", systemImage: "2.circle.fill")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Label("The selection is rewritten in place. ⌘Z to undo.", systemImage: "3.circle.fill")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            .padding(.vertical, DesignSystem.Spacing.lg)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private var noProviderBanner: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Add an LLM provider to apply Transforms")
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Transforms call your LLM provider on each run. Use Claude, GPT, Ollama, LM Studio — your key, your terms.")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer(minLength: DesignSystem.Spacing.md)

            Button("Open Settings", action: llmConfiguredAction)
                .parakeetAction(.primary)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.accentLight)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .stroke(DesignSystem.Colors.accent.opacity(0.25), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var myTransformsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("My Transforms")
                .font(DesignSystem.Typography.pageTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Button(action: onCreate) {
                Label("Create New", systemImage: "plus")
            }
            .parakeetAction(.primary)
        }
    }

    @ViewBuilder
    private var transformGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 260, maximum: 360), spacing: DesignSystem.Spacing.md, alignment: .top)
        ]
        LazyVGrid(columns: columns, alignment: .leading, spacing: DesignSystem.Spacing.md) {
            ForEach(viewModel.transforms) { transform in
                TransformCard(
                    transform: transform,
                    onEdit: { onEdit(transform) },
                    onDelete: {
                        viewModel.pendingDeleteTransform = transform
                    },
                    onReset: {
                        viewModel.resetBuiltIn(transform)
                        onBindingsChanged()
                    }
                )
            }

            CreateYourOwnTile(action: onCreate)
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button(action: {
                viewModel.reseedMissingBuiltIns()
                onBindingsChanged()
            }) {
                Label("Restore missing defaults", systemImage: "arrow.counterclockwise")
            }
            .parakeetAction(.subtle)
            Spacer()
        }
        .padding(.top, DesignSystem.Spacing.md)
    }
}

// MARK: - Transform card

private struct TransformCard: View {
    let transform: Prompt
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReset: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    if let shortcut = transform.shortcut {
                        KeycapBadge(shortcut: shortcut)
                    } else {
                        UnboundShortcutChip()
                    }
                    Spacer()
                    if isHovered {
                        cardActions
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(transform.name)
                        .font(DesignSystem.Typography.sectionTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Text(firstSentence(of: transform.content))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(3, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .stroke(isHovered ? DesignSystem.Colors.accent.opacity(0.35) : DesignSystem.Colors.border, lineWidth: 0.5)
            }
            .shadow(
                color: (isHovered ? DesignSystem.Shadows.cardHover : DesignSystem.Shadows.cardRest).color,
                radius: (isHovered ? DesignSystem.Shadows.cardHover : DesignSystem.Shadows.cardRest).radius,
                y: (isHovered ? DesignSystem.Shadows.cardHover : DesignSystem.Shadows.cardRest).y
            )
            .animation(DesignSystem.Animation.hoverTransition, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var cardActions: some View {
        HStack(spacing: 4) {
            if transform.isBuiltIn {
                Button("Reset", action: onReset)
                    .parakeetAction(.subtle)
                    .controlSize(.small)
            } else {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .parakeetAction(.subtle)
                .controlSize(.small)
                .help("Delete this Transform")
            }
        }
        .transition(.opacity)
    }

    private func firstSentence(of body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endIndex = trimmed.firstIndex(where: { ".!?".contains($0) }) else {
            return trimmed
        }
        return String(trimmed[..<endIndex]) + "."
    }
}

// MARK: - Create-your-own tile

private struct CreateYourOwnTile: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isHovered ? DesignSystem.Colors.accent : DesignSystem.Colors.textTertiary)
                Text("Create your own")
                    .font(DesignSystem.Typography.sectionTitle)
                    .foregroundStyle(isHovered ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                Text("Upload your own prompt")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .center)
            .background(isHovered ? DesignSystem.Colors.accentLight : DesignSystem.Colors.surfaceElevated.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .strokeBorder(
                        isHovered ? DesignSystem.Colors.accent.opacity(0.6) : DesignSystem.Colors.border,
                        style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
                    )
            }
            .animation(DesignSystem.Animation.hoverTransition, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Keycap badge

struct KeycapBadge: View {
    let shortcut: TransformShortcut

    var body: some View {
        HStack(spacing: 4) {
            ForEach(orderedModifierGlyphs, id: \.self) { glyph in
                Text(glyph)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 6)
                    .background(DesignSystem.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                    }
            }
            Text(shortcut.keyLabel.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, 6)
                .background(DesignSystem.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                }
        }
    }

    private var orderedModifierGlyphs: [String] {
        // Canonical macOS order: ⌃ ⌥ ⇧ ⌘.
        let ordered: [TransformShortcut.ModifierFlag] = [.control, .option, .shift, .command]
        return ordered
            .filter { (shortcut.modifiers & $0.rawValue) != 0 }
            .map(\.displayGlyph)
    }
}

private struct UnboundShortcutChip: View {
    var body: some View {
        Text("No shortcut bound")
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.surfaceElevated.opacity(0.5))
            .clipShape(Capsule())
    }
}
