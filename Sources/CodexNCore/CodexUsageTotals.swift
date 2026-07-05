import Foundation

struct CodexUsageTotals: Equatable {
    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var reasoningOutputTokens: UInt64 = 0
    var totalTokens: UInt64 = 0

    init() {}

    init(raw: [String: Any]) {
        inputTokens = Self.number(raw["input_tokens"])
            ?? Self.number(raw["prompt_tokens"])
            ?? Self.number(raw["input"])
            ?? 0
        cachedInputTokens = Self.number(raw["cached_input_tokens"])
            ?? Self.number(raw["cache_read_input_tokens"])
            ?? Self.number(raw["cached_tokens"])
            ?? 0
        outputTokens = Self.number(raw["output_tokens"])
            ?? Self.number(raw["completion_tokens"])
            ?? Self.number(raw["output"])
            ?? 0
        reasoningOutputTokens = Self.number(raw["reasoning_output_tokens"])
            ?? Self.number(raw["reasoning_tokens"])
            ?? 0
        totalTokens = Self.number(raw["total_tokens"]) ?? (inputTokens + outputTokens + reasoningOutputTokens)
    }

    mutating func add(_ other: CodexUsageTotals) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }

    func subtracting(_ previous: CodexUsageTotals?) -> CodexUsageTotals {
        guard let previous else { return self }
        return CodexUsageTotals(
            inputTokens: inputTokens.saturatingSubtract(previous.inputTokens),
            cachedInputTokens: cachedInputTokens.saturatingSubtract(previous.cachedInputTokens),
            outputTokens: outputTokens.saturatingSubtract(previous.outputTokens),
            reasoningOutputTokens: reasoningOutputTokens.saturatingSubtract(previous.reasoningOutputTokens),
            totalTokens: totalTokens.saturatingSubtract(previous.totalTokens)
        )
    }

    private init(
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64,
        reasoningOutputTokens: UInt64,
        totalTokens: UInt64
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    private static func number(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }
        if let value = value as? NSNumber {
            let raw = value.int64Value
            return raw >= 0 ? UInt64(raw) : nil
        }
        if let value = value as? String {
            return UInt64(value)
        }
        return nil
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self > other ? self - other : 0
    }
}
