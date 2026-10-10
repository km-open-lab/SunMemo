import Foundation
import CoreGraphics

/// Three aspect ratios for SunMemo sticky notes:
/// - "wide": 16:10 宽屏横版 (默认, 舒适横向排版, 视觉与截图并排协调)
/// - "square": 1:1 正方便利贴 (经典便利贴, 短备忘与灵感清单)
/// - "tall": 3:4 长条清单 (垂向待办列表、流程清单)
enum MemoAspectRatio: String, CaseIterable, Codable {
    case wide = "wide"
    case square = "square"
    case tall = "tall"

    var title: String {
        switch self {
        case .wide: return "宽版"
        case .square: return "方版"
        case .tall: return "竖版"
        }
    }

    var subtitle: String {
        switch self {
        case .wide: return "16:10 宽屏横版"
        case .square: return "1:1 正方便利贴"
        case .tall: return "3:4 长条清单"
        }
    }

    var symbol: String {
        switch self {
        case .wide: return "▭"
        case .square: return "□"
        case .tall: return "▯"
        }
    }

    /// Size of the card container on the clothesline
    var ropeSize: CGSize {
        switch self {
        case .wide: return CGSize(width: 220, height: 140)
        case .square: return CGSize(width: 160, height: 160)
        case .tall: return CGSize(width: 155, height: 210)
        }
    }

    /// Size of inner card content on clothesline
    var cardContentSize: CGSize {
        switch self {
        case .wide: return CGSize(width: 206, height: 122)
        case .square: return CGSize(width: 146, height: 142)
        case .tall: return CGSize(width: 141, height: 192)
        }
    }

    /// Size of the Hero preview modal card
    var previewSize: CGSize {
        switch self {
        case .wide: return CGSize(width: 510, height: 320)
        case .square: return CGSize(width: 400, height: 400)
        case .tall: return CGSize(width: 380, height: 500)
        }
    }

    /// Scrollview height inside the preview card
    var previewBodyHeight: CGFloat {
        switch self {
        case .wide: return 185
        case .square: return 265
        case .tall: return 365
        }
    }

    /// Recommended size for QuickMemo editor window
    var editorWindowSize: CGSize {
        switch self {
        case .wide: return CGSize(width: 500, height: 350)
        case .square: return CGSize(width: 420, height: 420)
        case .tall: return CGSize(width: 400, height: 490)
        }
    }
}
