import SwiftUI
import AppKit

/// Defines width and height bounds for customizable sticky notes,
/// preventing cards from becoming messy, overflowing, or unreadable.
public enum MemoLimits {
    /// Minimum width: guarantees text and actions remain properly readable.
    public static let minWidth: CGFloat = 130
    /// Maximum width: prevents a memo card from dominating the entire clothesline.
    public static let maxWidth: CGFloat = 300
    /// Minimum height: compact sticky note for single-line short memos like "一会去健身".
    public static let minHeight: CGFloat = 100
    /// Maximum height: ensures the card stays within the clothesline panel bounds (panel height 275).
    public static let maxHeight: CGFloat = 220

    public static func clampWidth(_ w: CGFloat) -> CGFloat {
        min(max(w, minWidth), maxWidth)
    }

    public static func clampHeight(_ h: CGFloat) -> CGFloat {
        min(max(h, minHeight), maxHeight)
    }
}

@MainActor
final class MemoTextPreferences: ObservableObject {
    static let shared = MemoTextPreferences()
    nonisolated static let key = "memoFontSize"
    nonisolated static let range = 12.0...24.0
    nonisolated static let defaultSize = 16.0

    @Published private(set) var fontSize: Double
    private let defaults: UserDefaults

    init(defaults: UserDefaults = Demo.defaults) {
        self.defaults = defaults
        fontSize = Self.savedSize(in: defaults)
    }

    nonisolated static func normalized(_ size: Double) -> Double {
        guard size.isFinite else { return defaultSize }
        return min(max(size.rounded(), range.lowerBound), range.upperBound)
    }

    nonisolated static func savedSize(in defaults: UserDefaults) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultSize }
        return normalized(defaults.double(forKey: key))
    }

    func setFontSize(_ size: Double) {
        fontSize = Self.normalized(size)
        defaults.set(fontSize, forKey: Self.key)
    }
}

struct MemoFontSizeControl: View {
    @ObservedObject private var preferences = MemoTextPreferences.shared

    var body: some View {
        HStack(spacing: 5) {
            Text(L("Font Size"))
                .font(.system(size: 11, weight: .medium))
            TextField(L("Font Size"), value: Binding(
                get: { preferences.fontSize }, set: { preferences.setFontSize($0) }
            ), format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 36)
            .accessibilityLabel(L("Memo Font Size"))
            Stepper(L("Font Size"), onIncrement: {
                preferences.setFontSize(preferences.fontSize + 1)
            }, onDecrement: {
                preferences.setFontSize(preferences.fontSize - 1)
            })
            .labelsHidden()
            .fixedSize()
        }
        .fixedSize()
        .help(L("Applies to all memos and remembers your last choice (12–24 pt)."))
    }
}

enum MemoCardLayout {
    static let headerHeight: CGFloat = 24

    static func textLayout(text: String, cardHeight: CGFloat, config: MemoTypographyConfig,
                           ratio: MemoAspectRatio) -> (maxLines: Int, showsMore: Bool) {
        let available = max(0, cardHeight - headerHeight - 20 - 18 - 8)
        let lineHeight = ceil(config.fontSize * 1.25)
        let lineStride = lineHeight + config.lineSpacing
        let count = text.components(separatedBy: "\n").count
        let presetLimit = ratio == .tall ? 7 : ratio == .square ? 5 : 4
        var limit = max(1, min(presetLimit, Int((available + config.lineSpacing) / lineStride)))
        let canShowMore = available >= lineHeight + 16
        if count > limit && canShowMore {
            limit = max(1, min(limit, Int((available - 16 + config.lineSpacing) / lineStride)))
        }
        return (limit, count > limit && canShowMore)
    }
}

/// The user's chosen text size, with weight and alignment adapted to the memo.
public struct MemoTypographyConfig {
    public let fontSize: CGFloat
    public let fontWeight: Font.Weight
    public let isSingleShortLine: Bool
    public let todoBoxSize: CGFloat
    public let lineSpacing: CGFloat
}

public enum MemoTypography {
    public static func config(for text: String, fontSize: CGFloat? = nil) -> MemoTypographyConfig {
        let rawLines = text.components(separatedBy: "\n")
        let nonBlankLines = rawLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let totalChars = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let size = fontSize ?? CGFloat(MemoTextPreferences.savedSize(in: Demo.defaults))
        let boxSize = min(max(size * 0.9, 12), 22)
        let spacing = max(3.5, size * 0.25)

        // 1. Ultra-short single line memo (e.g. "一会去健身" <= 12 chars)
        if nonBlankLines.count <= 1 && totalChars <= 12 {
            return MemoTypographyConfig(
                fontSize: size,
                fontWeight: .bold,
                isSingleShortLine: true,
                todoBoxSize: boxSize,
                lineSpacing: spacing
            )
        }

        // 2. Short memo (1-2 lines, <= 26 chars)
        if nonBlankLines.count <= 2 && totalChars <= 26 {
            return MemoTypographyConfig(
                fontSize: size,
                fontWeight: .semibold,
                isSingleShortLine: false,
                todoBoxSize: boxSize,
                lineSpacing: spacing
            )
        }

        // 3. Medium memo (<= 3 lines, <= 48 chars)
        if nonBlankLines.count <= 3 && totalChars <= 48 {
            return MemoTypographyConfig(
                fontSize: size,
                fontWeight: .medium,
                isSingleShortLine: false,
                todoBoxSize: boxSize,
                lineSpacing: spacing
            )
        }

        // 4. Standard / Multi-line checklist / long text
        return MemoTypographyConfig(
            fontSize: size,
            fontWeight: .medium,
            isSingleShortLine: false,
            todoBoxSize: boxSize,
            lineSpacing: spacing
        )
    }
}

/// A micro-tactile corner handle that allows the user to resize sticky notes
/// directly on the clothesline with live tactile feedback.
struct MemoResizeHandleView: View {
    let isResizing: Bool
    let onResizeDelta: (CGSize) -> Void
    let onResizeEnd: (CGSize) -> Void
    let onReset: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(isResizing ? 0.88 : 0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                )
                .frame(width: 17, height: 17)

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Color.black.opacity(isResizing ? 0.75 : 0.45))
                .frame(width: 17, height: 17)
        }
        .contentShape(Rectangle())
        .padding(3)
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    onResizeDelta(value.translation)
                }
                .onEnded { value in
                    onResizeEnd(value.translation)
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onReset()
            }
        )
        .help("拖动调整便签大小（双击恢复默认）")
    }
}
