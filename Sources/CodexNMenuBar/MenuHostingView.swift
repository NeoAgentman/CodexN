import AppKit
import SwiftUI

final class MenuHostingView<Content: View>: NSHostingView<Content> {
    private var measuredSize: NSSize?

    override var allowsVibrancy: Bool { true }

    override var intrinsicContentSize: NSSize {
        measuredSize ?? super.intrinsicContentSize
    }

    func applyMeasuredSize(width: CGFloat, height: CGFloat) {
        measuredSize = NSSize(width: width, height: height)
        frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        invalidateIntrinsicContentSize()
        layoutSubtreeIfNeeded()
    }
}
