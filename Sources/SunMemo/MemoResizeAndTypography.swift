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
    public static let minHeight: CGFloat = 72
    /// Maximum height: ensures the card stays within the clothesline panel bounds (panel height 275).
    public static let maxHeight: CGFloat = 220

    public static func clampWidth(_ w: CGFloat) -> CGFloat {
        min(max(w, minWidth), maxWidth)
    }

    public static func clampHeight(_ h: CGFloat) -> CGFloat {
        min(max(h, minHeight), maxHeight)
    }
}

/// Adaptive typography and layout rules for sticky notes.
/// Automatically enlarges font and centers text for short/single-line memos
/// so that short memos look full, punchy, and aesthetically balanced rather than empty.
public struct MemoTypographyConfig {
    public let fontSize: CGFloat
    public let fontWeight: Font.Weight
    public let isSingleShortLine: Bool
    public let todoBoxSize: CGFloat
    public let lineSpacing: CGFloat
}

public enum MemoTypography {
    public static func config(for text: String) -> MemoTypographyConfig {
        let rawLines = text.components(separatedBy: "\n")
        let nonBlankLines = rawLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let totalChars = text.trimmingCharacters(in: .whitespacesAndNewlines).count

        // 1. Ultra-short single line memo (e.g. "一会去健身" <= 12 chars)
        if nonBlankLines.count <= 1 && totalChars <= 12 {
            return MemoTypographyConfig(
                fontSize: 18.5,
                fontWeight: .bold,
                isSingleShortLine: true,
                todoBoxSize: 16,
                lineSpacing: 6
            )
        }

        // 2. Short memo (1-2 lines, <= 26 chars)
        if nonBlankLines.count <= 2 && totalChars <= 26 {
            return MemoTypographyConfig(
                fontSize: 15.0,
                fontWeight: .semibold,
                isSingleShortLine: false,
                todoBoxSize: 14.5,
                lineSpacing: 5
            )
        }

        // 3. Medium memo (<= 3 lines, <= 48 chars)
        if nonBlankLines.count <= 3 && totalChars <= 48 {
            return MemoTypographyConfig(
                fontSize: 13.0,
                fontWeight: .medium,
                isSingleShortLine: false,
                todoBoxSize: 13,
                lineSpacing: 4
            )
        }

        // 4. Standard / Multi-line checklist / long text
        return MemoTypographyConfig(
            fontSize: 11.5,
            fontWeight: .medium,
            isSingleShortLine: false,
            todoBoxSize: 12,
            lineSpacing: 3.5
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
