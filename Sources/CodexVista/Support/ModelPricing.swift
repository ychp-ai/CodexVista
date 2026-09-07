import Foundation

struct ModelCostBreakdown: Equatable, Sendable {
    var uncachedInputUSD = 0.0
    var cachedInputUSD = 0.0
    var visibleOutputUSD = 0.0
    var reasoningUSD = 0.0

    var totalUSD: Double {
        uncachedInputUSD + cachedInputUSD + visibleOutputUSD + reasoningUSD
    }

    mutating func add(_ other: ModelCostBreakdown) {
        uncachedInputUSD += other.uncachedInputUSD
        cachedInputUSD += other.cachedInputUSD
        visibleOutputUSD += other.visibleOutputUSD
        reasoningUSD += other.reasoningUSD
    }
}

struct ModelPricingRule: Equatable, Sendable {
    let modelID: String
    let inputPerMillionUSD: Double
    let cachedInputPerMillionUSD: Double
    let outputPerMillionUSD: Double
    let longContextThresholdTokens: Int?
    let longContextInputMultiplier: Double?
    let longContextOutputMultiplier: Double?
    let cacheWriteMultiplier: Double?

    func estimate(
        uncachedInputTokens: Int64,
        cachedInputTokens: Int64,
        visibleOutputTokens: Int64,
        reasoningTokens: Int64
    ) -> Double {
        estimateBreakdown(
            uncachedInputTokens: uncachedInputTokens,
            cachedInputTokens: cachedInputTokens,
            visibleOutputTokens: visibleOutputTokens,
            reasoningTokens: reasoningTokens
        ).totalUSD
    }

    func estimateBreakdown(
        uncachedInputTokens: Int64,
        cachedInputTokens: Int64,
        visibleOutputTokens: Int64,
        reasoningTokens: Int64
    ) -> ModelCostBreakdown {
        // These are aggregate token totals, not one request's context length.
        // Apply standard rates only; request-level surcharges cannot be reconstructed.
        ModelCostBreakdown(
            uncachedInputUSD: tokenCost(uncachedInputTokens, rate: inputPerMillionUSD),
            cachedInputUSD: tokenCost(cachedInputTokens, rate: cachedInputPerMillionUSD),
            visibleOutputUSD: tokenCost(visibleOutputTokens, rate: outputPerMillionUSD),
            reasoningUSD: tokenCost(reasoningTokens, rate: outputPerMillionUSD)
        )
    }

    func tokenCost(_ tokens: Int, rate: Double) -> Double {
        tokenCost(Int64(tokens), rate: rate)
    }

    private func tokenCost(_ tokens: Int64, rate: Double) -> Double {
        Double(max(tokens, 0)) / 1_000_000 * rate
    }
}

enum ModelPricingCatalog {
    // Astra verified on 2026-09-07; other standard API rates verified on 2026-09-04:
    // https://developers.openai.com/api/docs/models/<modelID>
    static let lastVerifiedDate = "2026-09-07"
    // Spark has no published API price; keep it out of publishedRules.
    static let referencePricedModelIDs = ["gpt-5.3-codex-spark"]
    static var listedModelIDs: [String] {
        publishedRules.map(\.modelID) + referencePricedModelIDs
    }

    static let publishedRules: [ModelPricingRule] = [
        ModelPricingRule(
            modelID: "gpt-6-astra",
            inputPerMillionUSD: 10,
            cachedInputPerMillionUSD: 1,
            outputPerMillionUSD: 50,
            // API metadata only; Codex Astra has no long-context surcharge or cache-write fee.
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: 1.25
        ),
        ModelPricingRule(
            modelID: "gpt-5.6-sol",
            inputPerMillionUSD: 4,
            cachedInputPerMillionUSD: 0.4,
            outputPerMillionUSD: 20,
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: 1.25
        ),
        ModelPricingRule(
            modelID: "gpt-5.6-terra",
            inputPerMillionUSD: 2,
            cachedInputPerMillionUSD: 0.2,
            outputPerMillionUSD: 12,
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: 1.25
        ),
        ModelPricingRule(
            modelID: "gpt-5.6-luna",
            inputPerMillionUSD: 0.2,
            cachedInputPerMillionUSD: 0.02,
            outputPerMillionUSD: 1.2,
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: 1.25
        ),
        ModelPricingRule(
            modelID: "gpt-5.5",
            inputPerMillionUSD: 5,
            cachedInputPerMillionUSD: 0.5,
            outputPerMillionUSD: 30,
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: nil
        ),
        ModelPricingRule(
            modelID: "gpt-5.4",
            inputPerMillionUSD: 2.5,
            cachedInputPerMillionUSD: 0.25,
            outputPerMillionUSD: 15,
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: nil
        ),
        ModelPricingRule(
            modelID: "gpt-5.4-mini",
            inputPerMillionUSD: 0.75,
            cachedInputPerMillionUSD: 0.075,
            outputPerMillionUSD: 4.5,
            longContextThresholdTokens: nil,
            longContextInputMultiplier: nil,
            longContextOutputMultiplier: nil,
            cacheWriteMultiplier: nil
        )
    ]

    static func rule(for modelID: String) -> ModelPricingRule? {
        explicitRule(for: modelID)
            ?? publishedRules.first { $0.modelID == "gpt-5.5" }
    }

    static func usesReferencePricing(for modelID: String) -> Bool {
        explicitRule(for: modelID) == nil
    }

    private static func explicitRule(for modelID: String) -> ModelPricingRule? {
        let lowercasedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedID = lowercasedID == "gpt-5.6"
            ? "gpt-5.6-sol"
            : lowercasedID
        return publishedRules.first { $0.modelID == normalizedID }
    }
}

enum ModelCostFormatter {
    static func usd(_ value: Double, approximate: Bool = false) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        let formatted: String
        if value >= 1 {
            formatted = String(format: "$%.2f", value)
        } else if value >= 0.01 {
            formatted = String(format: "$%.3f", value)
        } else {
            formatted = String(format: "$%.4f", value)
        }
        return approximate ? "≈" + formatted : formatted
    }

    static func rate(_ value: Double) -> String {
        let formatted = String(format: "$%.3f", value)
        return formatted.hasSuffix("0") ? String(formatted.dropLast()) : formatted
    }
}
