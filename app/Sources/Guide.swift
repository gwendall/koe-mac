import AppKit
import SwiftUI

// While System Settings shows the Accessibility list, a small card hangs
// under its window: turn Koe on here, and if Koe is not in the list, drag
// the bubble into it (macOS adds an app dropped there). It follows the
// window, steps away when System Settings is not in front, and leaves for
// good once Koe is allowed.
@MainActor
final class Guide {
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 86),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var timer: Timer?

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: GuideCard())
    }

    var isShown: Bool { timer != nil }

    func show() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        follow()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    // Under System Settings' window, centered, while it is in front.
    private func follow() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences",
              let frame = Self.settingsFrame() else { return panel.orderOut(nil) }
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) }?.visibleFrame ?? frame
        var origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY - size.height - 12)
        // No room below: over the window's bottom edge, inside it.
        if origin.y < screen.minY { origin.y = frame.minY + 16 }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    // System Settings' main window, in AppKit's coordinates (from the bottom left).
    private static func settingsFrame() -> NSRect? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier,
              let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              let primary = NSScreen.screens.first else { return nil }
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

struct GuideCard: View {
    var body: some View {
        HStack(spacing: 14) {
            BubbleIcon(size: 48)
                .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                .help(Words.say("Drag Koe into the list"))
            VStack(alignment: .leading, spacing: 3) {
                Text(Words.say("Turn Koe on in this list")).font(Brand.body(13, weight: .semibold))
                Text(Words.say("Not in it? Drag the bubble into the list."))
                    .font(Brand.body(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 340, height: 86)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Brand.gradient, lineWidth: 1.5))
    }
}
