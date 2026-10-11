import SwiftUI
import AppKit

/// Centralized animation design system for SunMemo (动效规范).
/// Three distinct animation tiers unify all motion across the app:
/// 1. 利落 (Snappy): 快速微交互、悬停让位、按钮响应、复选框打勾
/// 2. 轻柔 (Gentle): 界面展开收起、大窗口过渡、绳索垂降、平滑位移
/// 3. 弹性 (Bouncy): 卡片落绳、待办全部完成跳跃、触感回弹、微晃
enum Motion {
    /// 1. 利落 (Snappy) - response: 0.26, damping: 0.78
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.78)

    /// 2. 轻柔 (Gentle) - response: 0.40, damping: 0.82
    static let gentle = Animation.spring(response: 0.40, dampingFraction: 0.82)

    /// 3. 弹性 (Bouncy) - response: 0.34, damping: 0.62
    static let bouncy = Animation.spring(response: 0.34, dampingFraction: 0.62)

    /// 4. 卡片放大 (Hero open) - response: 0.46, damping: 0.84，略带回弹地飞向屏幕中央
    static let heroOpen = Animation.spring(response: 0.46, dampingFraction: 0.84)

    /// 5. 卡片收回 (Hero close) - response: 0.40, damping: 1.0，临界阻尼，精确落回绳上不冲出
    static let heroClose = Animation.spring(response: 0.40, dampingFraction: 1.0)

    /// Reduce Motion 下预览的淡入淡出
    static let heroFade = Animation.easeInOut(duration: 0.18)

    /// macOS 13 没有动画完成回调，收回动画结束后再关窗的兜底时长
    static let heroCloseFallback: TimeInterval = 0.45

    /// 悬停时卡片的抬升比例（以夹子为锚点放大，夹子仍留在绳上）
    static let hoverLift: CGFloat = 1.03

    /// 轻推：一次临界阻尼的快速推出，不在最高点停顿，紧接着由 nudgeReturn 接力回摆
    static let nudgePush = Animation.spring(response: 0.2, dampingFraction: 1.0)
    static let nudgeReturnDelay: TimeInterval = 0.16
    static let nudgeReturn = Animation.interpolatingSpring(stiffness: 38, damping: 2.4)

    /// 卡片落绳时的摆动，约 1.2 秒内停稳
    static let arriveSwing = Animation.interpolatingSpring(stiffness: 52, damping: 5.6)
    static let arriveAngle: Double = 10

    /// 0...1 之间的平滑阶梯，用来给同一个 progress 切出不同的淡入淡出区间
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 系统"减弱动态效果" (Reduce Motion) 开关
    static var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 根据减弱动态效果设置返回对应动画（若开启减弱动态效果，返回 nil 或轻微淡入淡出）
    static func springOrFade(_ animation: Animation) -> Animation? {
        shouldReduceMotion ? .easeInOut(duration: 0.18) : animation
    }
}

extension Animation {
    static var snappy: Animation { Motion.snappy }
    static var gentle: Animation { Motion.gentle }
    static var bouncy: Animation { Motion.bouncy }
}
