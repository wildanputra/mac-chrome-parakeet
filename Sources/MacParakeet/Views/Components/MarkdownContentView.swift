import SwiftUI
import AppKit

/// Block-level element parsed from a markdown string.
private enum MarkdownBlock {
    case heading(level: Int, content: String)
    case paragraph(content: String)
    case unorderedList(items: [String])
    case orderedList(items: [String])
    case codeBlock(language: String?, code: String)
    case blockquote(content: String)
    case thematicBreak
}

/// Renders markdown in a single NSTextView for full text selection and drag support.
/// Inline formatting (bold, italic, code, links, strikethrough) is handled within each block
/// via NSAttributedString markdown parsing.
struct MarkdownContentView: NSViewRepresentable {
    let content: String
    let baseFont: Font
    private let baseFontSize: CGFloat

    init(_ content: String, font: Font = DesignSystem.Typography.body) {
        self.content = content
        self.baseFont = font
        if font == DesignSystem.Typography.bodyLarge {
            self.baseFontSize = 15
        } else {
            self.baseFontSize = 14
        }
    }

    func makeNSView(context: Context) -> SelfSizingTextView {
        let wrapper = SelfSizingTextView()
        let textView = wrapper.textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        context.coordinator.wrapper = wrapper
        updateContent(wrapper)

        return wrapper
    }

    func updateNSView(_ wrapper: SelfSizingTextView, context: Context) {
        if content != context.coordinator.lastContent {
            context.coordinator.lastContent = content
            updateContent(wrapper)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastContent: String?
        weak var wrapper: SelfSizingTextView?
    }

    private func updateContent(_ wrapper: SelfSizingTextView) {
        let blocks = Self.parse(content)
        let attributed = buildAttributedString(blocks: blocks)
        wrapper.textView.textStorage?.setAttributedString(attributed)
        wrapper.invalidateIntrinsicContentSize()
    }

    // MARK: - Attributed String Building

    private func buildAttributedString(blocks: [MarkdownBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Bridge SwiftUI design tokens into appearance-aware NSColors. The
        // `NSColor(_ swiftuiColor:)` initializer preserves the dynamic light/dark
        // resolution of `Color(light:dark:)`.
        let textColor = NSColor(DesignSystem.Colors.textPrimary)
        let secondaryColor = NSColor(DesignSystem.Colors.textSecondary)
        let tertiaryColor = NSColor(DesignSystem.Colors.textTertiary)
        let accentColor = NSColor(DesignSystem.Colors.accent)

        let bodyFont = NSFont.systemFont(ofSize: baseFontSize)
        let bodyParagraphStyle = NSMutableParagraphStyle()
        bodyParagraphStyle.lineSpacing = 4
        bodyParagraphStyle.paragraphSpacing = 10

        for (index, block) in blocks.enumerated() {
            switch block {
            case let .heading(level, text):
                let font: NSFont
                switch level {
                case 1: font = NSFont.systemFont(ofSize: 22, weight: .semibold)
                case 2: font = NSFont.systemFont(ofSize: 17, weight: .semibold)
                case 3: font = NSFont.systemFont(ofSize: 15, weight: .semibold)
                default: font = NSFont.systemFont(ofSize: 14, weight: .semibold)
                }
                let style = NSMutableParagraphStyle()
                style.paragraphSpacing = 6
                if index > 0 { style.paragraphSpacingBefore = level <= 2 ? 12 : 8 }

                let headingStr = inlineAttributedString(text, baseFont: font, color: textColor)
                headingStr.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: headingStr.length))
                result.append(headingStr)
                result.append(NSAttributedString(string: "\n"))

            case let .paragraph(text):
                let paraStr = inlineAttributedString(text, baseFont: bodyFont, color: textColor)
                paraStr.addAttribute(.paragraphStyle, value: bodyParagraphStyle, range: NSRange(location: 0, length: paraStr.length))
                result.append(paraStr)
                result.append(NSAttributedString(string: "\n"))

            case let .unorderedList(items):
                let listStyle = NSMutableParagraphStyle()
                listStyle.lineSpacing = 3
                listStyle.paragraphSpacing = 5
                listStyle.headIndent = 20
                listStyle.firstLineHeadIndent = 4
                listStyle.tabStops = [NSTextTab(textAlignment: .natural, location: 20)]

                for (i, item) in items.enumerated() {
                    let bullet = NSMutableAttributedString(string: "\u{2022}\t", attributes: [
                        .font: bodyFont,
                        .foregroundColor: tertiaryColor,
                        .paragraphStyle: listStyle
                    ])
                    let itemStr = inlineAttributedString(item, baseFont: bodyFont, color: textColor)
                    itemStr.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: 0, length: itemStr.length))
                    bullet.append(itemStr)
                    result.append(bullet)
                    if i < items.count - 1 || index < blocks.count - 1 {
                        result.append(NSAttributedString(string: "\n"))
                    }
                }
                if index < blocks.count - 1 {
                    let spacer = NSMutableAttributedString(string: "\n")
                    let spacerStyle = NSMutableParagraphStyle()
                    spacerStyle.paragraphSpacing = 4
                    spacer.addAttribute(.paragraphStyle, value: spacerStyle, range: NSRange(location: 0, length: 1))
                    result.append(spacer)
                }

            case let .orderedList(items):
                let listStyle = NSMutableParagraphStyle()
                listStyle.lineSpacing = 3
                listStyle.paragraphSpacing = 5
                listStyle.headIndent = 28
                listStyle.firstLineHeadIndent = 4
                listStyle.tabStops = [NSTextTab(textAlignment: .natural, location: 28)]

                for (i, item) in items.enumerated() {
                    let marker = NSMutableAttributedString(string: "\(i + 1).\t", attributes: [
                        .font: bodyFont,
                        .foregroundColor: tertiaryColor,
                        .paragraphStyle: listStyle
                    ])
                    let itemStr = inlineAttributedString(item, baseFont: bodyFont, color: textColor)
                    itemStr.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: 0, length: itemStr.length))
                    marker.append(itemStr)
                    result.append(marker)
                    if i < items.count - 1 || index < blocks.count - 1 {
                        result.append(NSAttributedString(string: "\n"))
                    }
                }
                if index < blocks.count - 1 {
                    let spacer = NSMutableAttributedString(string: "\n")
                    let spacerStyle = NSMutableParagraphStyle()
                    spacerStyle.paragraphSpacing = 4
                    spacer.addAttribute(.paragraphStyle, value: spacerStyle, range: NSRange(location: 0, length: 1))
                    result.append(spacer)
                }

            case let .codeBlock(_, code):
                let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                let codeStyle = NSMutableParagraphStyle()
                codeStyle.lineSpacing = 2
                codeStyle.paragraphSpacing = 10

                // Apply the alpha inside a dynamic NSColor provider so the result
                // re-resolves on light/dark flip. We resolve `surfaceElevated` under
                // the supplied appearance, then attach the alpha — this keeps the
                // single source of truth (`DesignSystem.Colors.surfaceElevated`)
                // without snapping to the appearance that was current at first draw.
                let codeBackground = NSColor(name: nil) { appearance in
                    var resolved = NSColor.clear
                    appearance.performAsCurrentDrawingAppearance {
                        resolved = NSColor(DesignSystem.Colors.surfaceElevated)
                    }
                    return resolved.withAlphaComponent(0.7)
                }
                let codeStr = NSMutableAttributedString(string: code, attributes: [
                    .font: codeFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: codeStyle,
                    .backgroundColor: codeBackground
                ])
                result.append(codeStr)
                result.append(NSAttributedString(string: "\n"))

            case let .blockquote(text):
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.lineSpacing = 3
                quoteStyle.paragraphSpacing = 10
                quoteStyle.headIndent = 16
                quoteStyle.firstLineHeadIndent = 16

                let bar = NSMutableAttributedString(string: "\u{2503} ", attributes: [
                    .font: bodyFont,
                    .foregroundColor: accentColor.withAlphaComponent(0.4),
                    .paragraphStyle: quoteStyle
                ])
                let quoteStr = inlineAttributedString(text, baseFont: bodyFont, color: secondaryColor)
                quoteStr.addAttribute(.paragraphStyle, value: quoteStyle, range: NSRange(location: 0, length: quoteStr.length))
                bar.append(quoteStr)
                result.append(bar)
                result.append(NSAttributedString(string: "\n"))

            case .thematicBreak:
                let hrStyle = NSMutableParagraphStyle()
                hrStyle.paragraphSpacing = 10
                hrStyle.paragraphSpacingBefore = 10
                let hr = NSMutableAttributedString(string: "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: tertiaryColor.withAlphaComponent(0.4),
                    .paragraphStyle: hrStyle
                ])
                result.append(hr)
            }
        }

        // Trim trailing newline
        if result.length > 0, result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return result
    }

    private func inlineAttributedString(_ source: String, baseFont: NSFont, color: NSColor) -> NSMutableAttributedString {
        if let swiftAttr = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            let nsAttr = NSMutableAttributedString(swiftAttr)
            let fullRange = NSRange(location: 0, length: nsAttr.length)
            nsAttr.enumerateAttributes(in: fullRange) { attrs, range, _ in
                nsAttr.addAttribute(.foregroundColor, value: color, range: range)

                if let existingFont = attrs[.font] as? NSFont {
                    let traits = existingFont.fontDescriptor.symbolicTraits
                    var newFont = baseFont
                    if traits.contains(.bold) && traits.contains(.italic) {
                        newFont = NSFontManager.shared.convert(baseFont, toHaveTrait: [.boldFontMask, .italicFontMask])
                    } else if traits.contains(.bold) {
                        newFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold)
                    } else if traits.contains(.italic) {
                        newFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                    }
                    if existingFont.fontDescriptor.symbolicTraits.contains(.monoSpace) {
                        newFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
                    }
                    nsAttr.addAttribute(.font, value: newFont, range: range)
                } else {
                    nsAttr.addAttribute(.font, value: baseFont, range: range)
                }
            }
            return nsAttr
        }

        return NSMutableAttributedString(string: source, attributes: [
            .font: baseFont,
            .foregroundColor: color
        ])
    }

    // MARK: - Block Parser

    private static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if isUnorderedListItem(trimmed) {
                var items: [String] = []
                while index < lines.count {
                    let l = lines[index].trimmingCharacters(in: .whitespaces)
                    if isUnorderedListItem(l) {
                        items.append(String(l.dropFirst(2)))
                        index += 1
                    } else if l.isEmpty {
                        break
                    } else {
                        if !items.isEmpty {
                            items[items.count - 1] += " " + l
                        }
                        index += 1
                    }
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            if isOrderedListItem(trimmed) {
                var items: [String] = []
                while index < lines.count {
                    let l = lines[index].trimmingCharacters(in: .whitespaces)
                    if isOrderedListItem(l) {
                        items.append(stripOrderedMarker(l))
                        index += 1
                    } else if l.isEmpty {
                        break
                    } else {
                        if !items.isEmpty {
                            items[items.count - 1] += " " + l
                        }
                        index += 1
                    }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let l = lines[index].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    let dropCount = l.hasPrefix("> ") ? 2 : 1
                    quoteLines.append(String(l.dropFirst(dropCount)))
                    index += 1
                }
                blocks.append(.blockquote(content: quoteLines.joined(separator: "\n")))
                continue
            }

            var paraLines: [String] = []
            while index < lines.count {
                let t = lines[index].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("```") || isThematicBreak(t) ||
                   parseHeading(t) != nil || isUnorderedListItem(t) ||
                   isOrderedListItem(t) || t.hasPrefix(">") {
                    break
                }
                paraLines.append(t)
                index += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(content: paraLines.joined(separator: " ")))
            }
        }

        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for char in line {
            if char == "#" { level += 1 }
            else { break }
        }
        guard level >= 1, level <= 6,
              line.count > level,
              line[line.index(line.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        return .heading(level: level, content: String(line.dropFirst(level + 1)))
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return stripped.count >= 3 && (
            stripped.allSatisfy { $0 == "-" } ||
            stripped.allSatisfy { $0 == "*" } ||
            stripped.allSatisfy { $0 == "_" }
        )
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        guard let dotIndex = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isWholeNumber) else { return false }
        let afterDot = line.index(after: dotIndex)
        return afterDot < line.endIndex && line[afterDot] == " "
    }

    private static func stripOrderedMarker(_ line: String) -> String {
        guard let dotIndex = line.firstIndex(of: "."),
              line.index(after: dotIndex) < line.endIndex else { return line }
        return String(line[line.index(dotIndex, offsetBy: 2)...])
    }
}

// MARK: - Self-Sizing NSTextView Container

/// An NSView that wraps an NSTextView and reports its intrinsic content size
/// based on the text layout, so SwiftUI can size it correctly.
final class SelfSizingTextView: NSView {
    let textView: NSTextView = {
        let tv = NSTextView()
        tv.autoresizingMask = [.width]
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: usedRect.height)
    }

    override func layout() {
        super.layout()
        // When our width changes, the text reflows — recalculate height
        textView.textContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        invalidateIntrinsicContentSize()
    }
}
