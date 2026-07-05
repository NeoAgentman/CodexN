import Foundation

public enum TokenUsageChartLayout {
    public static func horizontalBarWidth(
        tokens: UInt64,
        maxTokens: UInt64,
        availableWidth: Double,
        minVisibleWidth: Double
    ) -> Double {
        guard tokens > 0, maxTokens > 0, availableWidth > 0 else { return 0 }
        let proportionalWidth = (Double(tokens) / Double(maxTokens)) * availableWidth
        return min(availableWidth, max(minVisibleWidth, proportionalWidth))
    }
}
