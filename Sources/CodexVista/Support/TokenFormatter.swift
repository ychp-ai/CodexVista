import Foundation

enum TokenFormatter {
    static func rateWithUnit(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return "\(rate(value)) Token/s"
    }

    static func rate(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        switch value {
        case 1_000_000_000...: return String(format: "%.1fB", value / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "%.1fK", value / 1_000)
        case 0: return "0"
        case ..<0.1: return "<0.1"
        default: return String(format: "%.1f", value)
        }
    }

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...:
            String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:
            String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            String(format: "%.1fK", Double(value) / 1_000)
        default:
            String(value)
        }
    }

    static func percentage(_ value: Double) -> String {
        let normalized = value.isFinite ? min(max(value, 0), 1) : 0
        return String(format: "%.1f%%", normalized * 100)
    }

    static func worktime(_ milliseconds: Int64) -> String {
        if milliseconds > 0, milliseconds < 60_000 {
            return "少于 1 分钟"
        }
        let totalMinutes = max(0, Int(Double(milliseconds) / 60_000))
        let days = totalMinutes / 1_440
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if milliseconds >= 86_400_000 {
            let remainingHours = hours % 24
            var components = ["\(days) 天"]
            if remainingHours > 0 { components.append("\(remainingHours) 小时") }
            if minutes > 0 { components.append("\(minutes) 分钟") }
            return components.joined(separator: " ")
        }
        if hours == 0 {
            return "\(minutes) 分钟"
        }
        if minutes == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    static func compactWorktime(_ milliseconds: Int64) -> String {
        if milliseconds > 0, milliseconds < 60_000 {
            return "<1m"
        }
        let totalMinutes = max(0, Int(Double(milliseconds) / 60_000))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if milliseconds >= 86_400_000 {
            let totalHours = max(24, Int(Double(milliseconds) / 3_600_000))
            let days = totalHours / 24
            let remainingHours = totalHours % 24
            return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
        }
        if hours == 0 {
            return "\(minutes)m"
        }
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}
