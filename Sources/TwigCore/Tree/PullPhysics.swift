import CoreGraphics
import Foundation

public struct PullSession {
    public var targetOffset: CGSize = .zero   // 手的目标位移（起点偏移 + 拖拽 × 0.9）
    public var offset: CGSize = .zero         // 树的实际偏移（积分值）
    public var consumed: CGFloat = 0          // 已消耗的拉力
    public var peakRaw: CGFloat = 0           // 峰值拔力（猛拽冲线算数）
    public var velocity: CGSize = .zero       // 本帧位移（枝干张力弯曲用）
    public init() {}
}

public enum PullPhysics {
    public static let follow: CGFloat = 0.4
    public static let gravityBase: CGFloat = 2.2
    public static let gravityRate: CGFloat = 0.02
    public static let revealSlack: CGFloat = 20
    public static let hotRatio: CGFloat = 0.65

    /// 一帧：跟随积分 + 重力回吸 + 速度记录
    public static func step(_ s: inout PullSession, direction: PullDirection) {
        let prev = s.offset
        s.offset.width += (s.targetOffset.width - s.offset.width) * follow
        s.offset.height += (s.targetOffset.height - s.offset.height) * follow

        // 重力：主轴往土壤吸 + 交叉轴回正
        if direction == .up || direction == .down {
            s.offset.height -= (s.offset.height > 0 ? 1 : s.offset.height < 0 ? -1 : 0)
                * min(abs(s.offset.height), gravityBase + abs(s.offset.height) * gravityRate)
            s.offset.width -= (s.offset.width > 0 ? 1 : s.offset.width < 0 ? -1 : 0)
                * min(abs(s.offset.width), 0.8)
        } else {
            s.offset.width -= (s.offset.width > 0 ? 1 : s.offset.width < 0 ? -1 : 0)
                * min(abs(s.offset.width), gravityBase + abs(s.offset.width) * gravityRate)
            s.offset.height -= (s.offset.height > 0 ? 1 : s.offset.height < 0 ? -1 : 0)
                * min(abs(s.offset.height), 0.8)
        }
        s.velocity = CGSize(width: s.offset.width - prev.width, height: s.offset.height - prev.height)

        // 峰值拔力（沿拖拽方向）
        let raw = rawPull(s, direction: direction)
        s.peakRaw = max(s.peakRaw, raw)
    }

    /// 沿拖拽方向的瞬时拔出量（恒正）
    public static func rawPull(_ s: PullSession, direction: PullDirection) -> CGFloat {
        switch direction {
        case .up: return -s.offset.height
        case .down: return s.offset.height
        case .left: return -s.offset.width
        case .right: return s.offset.width
        }
    }

    /// 有效拔力 = 峰值 − 已消耗
    public static func pullMain(_ s: PullSession, direction: PullDirection) -> CGFloat {
        max(s.peakRaw, rawPull(s, direction: direction)) - s.consumed
    }

    /// 出土判定：有效拔力超过埋深 ⇒ 出土并消耗拉力
    public static func checkReveal(_ s: inout PullSession, direction: PullDirection,
                                   buriedDepth: CGFloat) -> Bool {
        if pullMain(s, direction: direction) > buriedDepth + revealSlack {   // 原型：threshold = 埋深+20
            s.consumed += buriedDepth
            return true
        }
        return false
    }

    /// easeOutBack（松手回弹曲线，t∈[0,1]，中途略过 1 为过冲）
    public static func springEase(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
}
