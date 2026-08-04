import SwiftUI
import TwigCore

/// 节点卡：主体只有阶段名；期限/进度/任务数做成右侧小卫星
struct NodeCardView: View {
    let goal: Goal
    let color: Color
    var isBuried: Bool = false
    var isFocusing: Bool = false

    private var total: Int { goal.tasks.count }
    private var done: Int { goal.tasks.filter(\.isDone).count }
    private var openCount: Int { total - done }
    private var frac: Double { total > 0 ? Double(done) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 7) {
            cardBody
            satellite
        }
        .opacity(isBuried ? 0.22 : 1)
        .saturation(isBuried ? 0.6 : 1)
    }

    /// 卡片主体：毛玻璃 + 衬线标题 + 项目色左边条
    private var cardBody: some View {
        Text(goal.title)
            .font(.system(size: 12, weight: .semibold, design: .serif))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(.white.opacity(0.62))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.leading, 1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.85), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }

    /// 右侧小卫星：期限 tag → 迷你进度条 → done/total → 红点任务数。
    /// 不做 allowsHitTesting(false)：卫星区占卡片右半，点不穿的话从右半边拖节点
    /// 会落空到下层空白层（变成拖窗口）——卫星无可点元素，命中归节点即可
    private var satellite: some View {
        HStack(spacing: 4) {
            Text(tagText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tagColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(.white.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.8), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.07)).frame(width: 26, height: 3)
                Capsule().fill(done == total && total > 0 ? Color(red: 0.49, green: 0.61, blue: 0.46) : color)
                    .frame(width: 26 * frac, height: 3)
            }
            Text("\(done)/\(total)")
                .font(.system(size: 9))
                .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.42))
                .monospacedDigit()
            Text("\(openCount)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .frame(minWidth: 15, minHeight: 15)
                .background(color, in: Circle())
        }
    }

    private var tagText: String {
        let base = goal.horizon == .short ? "短期" : goal.horizon == .mid ? "中期" : "长期"
        if let d = goal.targetDate {
            let fmt = DateFormatter()
            fmt.dateFormat = "M/d"
            return base + " " + fmt.string(from: d)
        }
        return base
    }

    private var tagColor: Color {
        switch goal.horizon {
        case .short: return Color(red: 0.85, green: 0.47, blue: 0.34)   // #D97757
        case .mid: return Color(red: 0.42, green: 0.56, blue: 0.77)     // #6B8FC4
        case .long: return Color(red: 0.65, green: 0.64, blue: 0.62)    // #A6A49E
        }
    }
}
