import AppKit
import CodexNCore
import Foundation
import SwiftUI

struct TokenUsageMenuChart: View {
    let snapshot: CodexUsageSnapshot?

    @State private var hoverTooltip: TokenUsageHoverTooltip?

    private let width: CGFloat = 300
    private let usageValueWidth: CGFloat = 58
    private let usageBarHeight: CGFloat = 8
    private let usageRowHeight: CGFloat = 18
    private let usageRowSpacing: CGFloat = 7
    private let usageBarMinVisibleWidth: CGFloat = 6
    private let hoverIDMaxLength = 24
    private let colors: [Color] = [
        Color(red: 0.26, green: 0.55, blue: 0.96),
        Color(red: 0.46, green: 0.72, blue: 0.38),
        Color(red: 0.94, green: 0.58, blue: 0.24),
        Color(red: 0.72, green: 0.40, blue: 0.86),
        Color(red: 0.25, green: 0.70, blue: 0.78),
        Color(red: 0.86, green: 0.34, blue: 0.42)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Token Usage")
                .font(.caption.weight(.semibold))

            if let snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(totalLabel)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Updated \(Self.timeString(snapshot.generatedAt))")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    Spacer(minLength: 0)
                }

                if snapshot.profiles.isEmpty {
                    emptyState("No usage data today")
                } else {
                    usageList(for: snapshot.profiles)
                }
            } else {
                emptyState("Usage data is updating")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
    }

    private var totalLabel: String {
        guard let snapshot else { return "Updating" }
        return "\(TokenUsageFormatting.tokenString(snapshot.totalTokens)) today"
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private func usageList(for profiles: [CodexUsageProfileSnapshot]) -> some View {
        let maxTokens = max(profiles.map(\.totalTokens).max() ?? 0, 1)
        let availableWidth = width - 24
        let barAvailableWidth = max(1, availableWidth - usageValueWidth - 10)
        let listHeight = CGFloat(profiles.count) * usageRowHeight + CGFloat(max(0, profiles.count - 1)) * usageRowSpacing

        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: usageRowSpacing) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    HStack(spacing: 10) {
                        Text(TokenUsageFormatting.shortTokenString(profile.totalTokens))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: usageValueWidth, alignment: .trailing)

                        ZStack(alignment: .leading) {
                            if profile.totalTokens > 0 {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(colors[index % colors.count].gradient)
                                    .frame(
                                        width: usageBarWidth(
                                            tokens: profile.totalTokens,
                                            maxTokens: maxTokens,
                                            availableWidth: barAvailableWidth
                                        ),
                                        height: usageBarHeight
                                    )
                                    .shadow(
                                        color: colors[index % colors.count].opacity(hoverTooltip?.profileID == profile.id ? 0.32 : 0),
                                        radius: 4,
                                        y: 1
                                    )
                            }
                        }
                        .frame(width: barAvailableWidth, height: usageRowHeight, alignment: .leading)
                        .accessibilityLabel(profile.name)
                        .accessibilityValue(TokenUsageFormatting.tokenString(profile.totalTokens))
                    }
                    .frame(width: availableWidth, height: usageRowHeight, alignment: .leading)
                }
            }
            .frame(width: availableWidth, height: listHeight, alignment: .leading)

            TokenUsageMouseTrackingView { location in
                hoverTooltip = usageListTooltip(at: location, profiles: profiles)
            } onExit: {
                hoverTooltip = nil
            }
            .frame(width: availableWidth, height: listHeight)

            if let hoverTooltip {
                hoverTooltipView(hoverTooltip)
                    .offset(
                        x: tooltipX(for: hoverTooltip, availableWidth: availableWidth),
                        y: tooltipY(for: hoverTooltip.location, containerHeight: listHeight)
                    )
                    .zIndex(2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: availableWidth, height: listHeight, alignment: .leading)
        .frame(maxWidth: .infinity, minHeight: listHeight, maxHeight: listHeight, alignment: .leading)
    }

    private func usageBarWidth(tokens: UInt64, maxTokens: UInt64, availableWidth: CGFloat) -> CGFloat {
        CGFloat(
            TokenUsageChartLayout.horizontalBarWidth(
                tokens: tokens,
                maxTokens: maxTokens,
                availableWidth: Double(availableWidth),
                minVisibleWidth: Double(usageBarMinVisibleWidth)
            )
        )
    }

    private func usageListTooltip(
        at location: CGPoint,
        profiles: [CodexUsageProfileSnapshot]
    ) -> TokenUsageHoverTooltip? {
        let stride = usageRowHeight + usageRowSpacing
        guard stride > 0 else { return nil }
        let index = Int(location.y / stride)
        guard profiles.indices.contains(index) else { return nil }
        let rowY = CGFloat(index) * stride
        guard location.y >= rowY, location.y <= rowY + usageRowHeight else { return nil }
        let profile = profiles[index]
        return TokenUsageHoverTooltip(profileID: profile.id, location: location)
    }

    private func hoverTooltipView(_ tooltip: TokenUsageHoverTooltip) -> some View {
        Text(truncatedHoverID(tooltip.profileID))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .fixedSize(horizontal: true, vertical: false)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
            )
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private func tooltipX(for tooltip: TokenUsageHoverTooltip, availableWidth: CGFloat) -> CGFloat {
        let width = estimatedTooltipWidth(for: truncatedHoverID(tooltip.profileID))
        return max(0, min(tooltip.location.x + 12, availableWidth - width))
    }

    private func tooltipY(for location: CGPoint, containerHeight: CGFloat) -> CGFloat {
        max(0, min(location.y - 10, containerHeight - 26))
    }

    private func truncatedHoverID(_ value: String) -> String {
        guard value.count > hoverIDMaxLength else { return value }
        return "\(value.prefix(max(0, hoverIDMaxLength - 3)))..."
    }

    private func estimatedTooltipWidth(for value: String) -> CGFloat {
        min(180, CGFloat(value.count) * 7 + 14)
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct TokenUsageHoverTooltip: Equatable {
    let profileID: String
    let location: CGPoint
}

struct TokenUsageMouseTrackingView: NSViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onExit: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func mouseMoved(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onMove?(CGPoint(x: location.x, y: bounds.height - location.y))
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }
    }
}
