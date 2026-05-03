import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

struct CustomWordsView: View {
    @Bindable var viewModel: CustomWordsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredCardTitle: String?
    @State private var hoveredWordID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                headerCard
                searchCard
                wordsCard
                addWordCard
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(.thickMaterial)
        .alert(
            "Delete Word?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteWord != nil },
                set: { if !$0 { viewModel.pendingDeleteWord = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteWord = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            if let word = viewModel.pendingDeleteWord {
                Text("Delete \"\(word.word)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        managementCard(
            title: "Custom Words",
            subtitle: "Teach MacParakeet how you say things.",
            icon: "character.book.closed"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: DesignSystem.Spacing.sm)],
                spacing: DesignSystem.Spacing.sm
            ) {
                metricChip(title: "Total", value: "\(viewModel.words.count)")
                metricChip(title: "Visible", value: "\(viewModel.filteredWords.count)")
                metricChip(title: "Enabled", value: "\(viewModel.words.filter(\.isEnabled).count)")
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .parakeetAction(.primaryProminent)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var searchCard: some View {
        managementCard(
            title: "Search",
            subtitle: "Filter by source word or replacement.",
            icon: "magnifyingglass"
        ) {
            TextField("Search words...", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var wordsCard: some View {
        managementCard(
            title: "Word Rules",
            subtitle: "Toggle to enable or disable each rule.",
            icon: "list.bullet"
        ) {
            if viewModel.filteredWords.isEmpty {
                emptyWordsState
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(viewModel.filteredWords) { word in
                        wordRow(word)
                    }
                }
            }
        }
    }

    private var addWordCard: some View {
        managementCard(
            title: "Add Rule",
            subtitle: "Add a word to correct, or leave replacement blank to enforce its spelling.",
            icon: "plus.circle"
        ) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.errorRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    TextField("Word or phrase", text: $viewModel.newWord)
                        .textFieldStyle(.roundedBorder)
                        .focused($wordFieldFocused)
                    TextField("Replacement (optional)", text: $viewModel.newReplacement)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        viewModel.addWord()
                    }
                    .parakeetAction(.primaryProminent)
                    .disabled(viewModel.newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Rows

    private func wordRow(_ word: CustomWord) -> some View {
        let isHovered = hoveredWordID == word.id
        let toggleHint: String = word.replacement.map { "Replaces with \($0)" } ?? "Enforces exact spelling"
        return HStack(spacing: DesignSystem.Spacing.md) {
            Toggle("", isOn: Binding(
                get: { word.isEnabled },
                set: { _ in viewModel.toggleEnabled(word) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("Enable \(word.word)")
            .accessibilityHint(toggleHint)

            VStack(alignment: .leading, spacing: 3) {
                Text(word.word)
                    .font(DesignSystem.Typography.body)
                    .opacity(word.isEnabled ? 1.0 : 0.55)

                if let replacement = word.replacement {
                    Text("Replaces with: \(replacement)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enforces exact spelling")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                viewModel.pendingDeleteWord = word
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete \(word.word)")
            .accessibilityLabel("Delete \(word.word)")
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(isHovered ? DesignSystem.Colors.rowHoverBackground : DesignSystem.Colors.surfaceElevated)
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                hoveredWordID = hovering ? word.id : nil
            }
        }
    }

    @FocusState private var wordFieldFocused: Bool

    private var emptyWordsState: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "character.textbox")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(viewModel.words.isEmpty ? "No custom words yet" : "No matches")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
            if viewModel.words.isEmpty {
                Text("Add words to fix spelling or capitalization that the speech engine gets wrong.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button("Add Your First Rule") {
                    wordFieldFocused = true
                }
                .parakeetAction(.primaryProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.lg)
    }

    // MARK: - Reusable

    private func managementCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isHovered = hoveredCardTitle == title
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Typography.sectionTitle)
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.cardBackground)
                .cardShadow(isHovered ? DesignSystem.Shadows.cardHover : DesignSystem.Shadows.cardRest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(
                    isHovered ? DesignSystem.Colors.accent.opacity(0.2) : DesignSystem.Colors.border.opacity(0.6),
                    lineWidth: 0.5
                )
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                hoveredCardTitle = hovering ? title : nil
            }
        }
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignSystem.Typography.micro)
                .foregroundStyle(.secondary)
            Text(value)
                .font(DesignSystem.Typography.body.weight(.semibold))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated)
        )
    }
}
