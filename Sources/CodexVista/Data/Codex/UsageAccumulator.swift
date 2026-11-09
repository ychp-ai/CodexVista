struct TokenUsageDelta: Equatable, Sendable {
    let uncachedInput: Int64
    let cachedInput: Int64
    let visibleOutput: Int64
    let reasoning: Int64

    var total: Int64 {
        uncachedInput + cachedInput + visibleOutput + reasoning
    }
}

enum UsageAccumulator {
    static func delta(previous: TokenCounters, current: TokenCounters) -> TokenUsageDelta? {
        let counters: TokenCounters
        if current.input >= previous.input,
           current.cachedInput >= previous.cachedInput,
           current.output >= previous.output,
           current.reasoning >= previous.reasoning {
            counters = TokenCounters(
                input: current.input - previous.input,
                cachedInput: current.cachedInput - previous.cachedInput,
                output: current.output - previous.output,
                reasoning: current.reasoning - previous.reasoning
            )
        } else {
            counters = current
        }

        let result = TokenUsageDelta(
            uncachedInput: max(counters.input - counters.cachedInput, 0),
            cachedInput: counters.cachedInput,
            visibleOutput: max(counters.output - counters.reasoning, 0),
            reasoning: counters.reasoning
        )
        return result.total == 0 ? nil : result
    }
}

enum PlanResolver {
    static func resolve(rawValue: String?) -> PlanResolution {
        let kind: PlanKind?
        switch rawValue?.lowercased() {
        case "free":
            kind = .free
        case "go":
            kind = .go
        case "plus":
            kind = .plus
        case "prolite":
            kind = .proLite
        case "pro":
            kind = .pro20x
        case "promax":
            kind = .proMax
        case "team", "business":
            kind = .businessStandard
        case "self_serve_business_prolite":
            kind = .businessPremium
        case "enterprise":
            kind = .enterprise
        case "edu":
            kind = .edu
        default:
            kind = nil
        }

        return PlanResolution(
            kind: kind ?? .free,
            rawValue: rawValue,
            isInferred: kind == nil
        )
    }
}

enum QuotaKind: String, Codable, Sendable {
    case fiveHour
    case weekly
}

struct QuotaObservation: Equatable, Sendable {
    let kind: QuotaKind
    let observedAtMilliseconds: Int64
    let windowMinutes: Int
    let remaining: Double
    let resetsAtMilliseconds: Int64?
    let plan: PlanResolution
}

enum QuotaNormalizer {
    static func normalize(
        _ windows: [RawQuotaWindow],
        plan: PlanResolution,
        observedAtMilliseconds: Int64
    ) -> [QuotaObservation] {
        windows.compactMap { window in
            let kind: QuotaKind
            switch window.windowMinutes {
            case 300:
                kind = .fiveHour
            case 10_080:
                kind = .weekly
            default:
                return nil
            }

            return QuotaObservation(
                kind: kind,
                observedAtMilliseconds: observedAtMilliseconds,
                windowMinutes: window.windowMinutes,
                remaining: min(max(1 - window.usedPercent / 100, 0), 1),
                resetsAtMilliseconds: window.resetsAtSeconds.map { $0 * 1_000 },
                plan: plan
            )
        }
    }
}
