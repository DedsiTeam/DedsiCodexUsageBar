import Foundation

struct UsageResponse: Decodable, Sendable {
    let planType: String?
    let rateLimit: RateLimitPayload?
    let credits: CreditsPayload?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }
}

struct RateLimitPayload: Decodable, Sendable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: RateLimitWindow?
    let secondaryWindow: RateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct RateLimitWindow: Decodable, Sendable, Identifiable {
    var id: String { "\(limitWindowSeconds ?? -1)-\(resetAt ?? -1)-\(usedPercent)" }

    let usedPercent: Double
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    var clampedPercent: Double {
        min(max(usedPercent, 0), 100)
    }

    var title: String {
        switch limitWindowSeconds {
        case 18_000:
            return "5 小时"
        case 604_800:
            return "每周"
        case let .some(seconds) where seconds % 86_400 == 0:
            return "\(seconds / 86_400) 天"
        case let .some(seconds) where seconds % 3_600 == 0:
            return "\(seconds / 3_600) 小时"
        case let .some(seconds):
            return "\(seconds) 秒"
        case .none:
            return "额度"
        }
    }
}

struct CreditsPayload: Decodable, Sendable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: FlexibleNumber?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}

enum FlexibleNumber: Decodable, Sendable {
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.typeMismatch(
            FlexibleNumber.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected number or string")
        )
    }

    var display: String? {
        switch self {
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(format: "%.2f", value)
        case .string(let value):
            return value.isEmpty ? nil : value
        }
    }
}

struct DisplayWindow: Identifiable, Equatable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetText: String
}

enum UsageFormatting {
    static func windows(from response: UsageResponse) -> [DisplayWindow] {
        let raw = [
            response.rateLimit?.primaryWindow,
            response.rateLimit?.secondaryWindow,
        ].compactMap { $0 }

        return raw.map { window in
            DisplayWindow(
                id: window.id,
                title: window.title,
                usedPercent: window.clampedPercent,
                resetText: resetText(for: window)
            )
        }
    }

    static func menuBarTitle(windows: [DisplayWindow], error: String?) -> String {
        if error != nil {
            return "C —"
        }
        guard !windows.isEmpty else {
            return "C —"
        }
        let parts = windows.map { "\(Int($0.usedPercent.rounded()))%" }
        return "C " + parts.joined(separator: " · ")
    }

    static func resetText(for window: RateLimitWindow) -> String {
        if let seconds = window.resetAfterSeconds, seconds >= 0 {
            return "重置倒计时 \(formatDuration(seconds))"
        }
        if let resetAt = window.resetAt {
            let remaining = max(0, Int(resetAt - Date().timeIntervalSince1970))
            return "重置倒计时 \(formatDuration(remaining))"
        }
        return "重置时间未知"
    }

    static func formatDuration(_ totalSeconds: Int) -> String {
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if days > 0 {
            if hours > 0 {
                return "\(days)天\(hours)小时"
            }
            return "\(days)天"
        }
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)小时\(minutes)分"
            }
            return "\(hours)小时"
        }
        return "\(max(minutes, 0))分"
    }

    static func relativeUpdated(_ date: Date?) -> String {
        guard let date else { return "尚未更新" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 15 {
            return "刚刚更新"
        }
        if seconds < 60 {
            return "\(seconds)秒前更新"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)分钟前更新"
        }
        return "\(minutes / 60)小时前更新"
    }
}
