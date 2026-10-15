import AppKit
import QuartzCore

// The dictation's own small pill, low in the middle of the screen you work
// on: five bars and nothing to read. Flat and gray the moment the shortcut
// goes down and whenever no voice comes in, dancing with the voice, a wave
// while the words are worked out, a check when they land. Anything Koe has
// to say goes up in the toast instead (docs/brand.md).
@MainActor
final class Indicator {
    static let size = CGSize(width: 66, height: 30)
    private static let margin: CGFloat = 20 // room for the glow and the springs
    private static let lift: CGFloat = 26   // above the Dock, or the screen's edge
    private static let barCount = 5, barWidth: CGFloat = 4, barGap: CGFloat = 3, barMax: CGFloat = 16, barRest: CGFloat = 4
    // Each bar's share of the level, so they move as a voice does, not in step.
    private static let barShape: [CGFloat] = [0.55, 0.9, 1, 0.75, 0.5]
    private static let check = ["......##", ".....##.", "##..##..", ".####...", "..##...."]
    private static let quiet = Pixels.ink.copy(alpha: 0.32)!

    let host = NSView()
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var stage: CALayer?
    private var bars: [CALayer] = []
    private var working = false
    private var generation = 0

    // What the evals take a picture of.
    var window: NSWindow { panel }

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        host.wantsLayer = true
        panel.contentView = host
    }

    // In, flat and gray: Koe listens, nothing heard yet. On the screen with
    // the pointer, where you are working.
    func show() {
        generation += 1
        working = false
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        let size = NSSize(width: Self.size.width + 2 * Self.margin, height: Self.size.height + 2 * Self.margin)
        if let area = screen?.visibleFrame {
            panel.setFrame(NSRect(x: (area.midX - size.width / 2).rounded(), y: area.minY + Self.lift - Self.margin, width: size.width, height: size.height),
                           display: false)
        }
        host.frame = NSRect(origin: .zero, size: size)
        let root = host.layer!
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        let bounds = CGRect(origin: .zero, size: Self.size)
        let radius = bounds.height / 2
        let stage = CALayer()
        stage.bounds = bounds
        stage.anchorPoint = CGPoint(x: 0.5, y: 0)
        stage.position = CGPoint(x: size.width / 2, y: Self.margin)
        root.addSublayer(stage)
        self.stage = stage

        let halo = CALayer()
        halo.frame = bounds
        halo.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        halo.shadowColor = Pixels.glow
        halo.shadowOpacity = 0.4
        halo.shadowRadius = 10
        halo.shadowOffset = .zero
        stage.addSublayer(halo)

        let pill = CAGradientLayer()
        pill.frame = bounds
        pill.cornerRadius = radius
        pill.masksToBounds = true
        pill.colors = Pixels.candy
        pill.startPoint = CGPoint(x: 0, y: 0.5)
        pill.endPoint = CGPoint(x: 1, y: 0.5)
        stage.addSublayer(pill)

        bars = []
        let span = CGFloat(Self.barCount) * Self.barWidth + CGFloat(Self.barCount - 1) * Self.barGap
        var x = (bounds.width - span) / 2
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.backgroundColor = Self.quiet
            bar.cornerRadius = 1
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barRest)
            bar.position = CGPoint(x: x + Self.barWidth / 2, y: bounds.height / 2)
            pill.addSublayer(bar)
            bars.append(bar)
            x += Self.barWidth + Self.barGap
        }

        panel.orderFrontRegardless()
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            Motion.basic(stage, "opacity", from: 0, to: 1, at: now, duration: 0.15)
        } else {
            Motion.spring(stage, "transform.scale", from: 0.8, to: 1, at: now, omega: 18, zeta: 0.7)
            Motion.spring(stage, "transform.translation.y", from: -10, to: 0, at: now, omega: 18, zeta: 0.75)
            Motion.basic(stage, "opacity", from: 0, to: 1, at: now, duration: 0.1)
        }
        CATransaction.commit()
    }

    // The voice's level, 0 to 1: the bars stand up in ink, or lie down gray.
    func setLevel(_ level: Float) {
        guard !working, !bars.isEmpty else { return }
        let level = CGFloat(max(0, min(1, level)))
        let heard = level > 0.05
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        for (index, bar) in bars.enumerated() {
            let jitter = CGFloat.random(in: 0.8...1.15)
            let height = heard ? min(Self.barMax, max(Self.barRest, (Self.barMax * level * Self.barShape[index] * jitter).rounded())) : Self.barRest
            bar.bounds.size.height = height
            bar.backgroundColor = heard ? Pixels.ink : Self.quiet
        }
        CATransaction.commit()
    }

    // The words being worked out: a wave runs through the bars.
    func work() {
        guard !bars.isEmpty else { return }
        working = true
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = Pixels.ink
            bar.bounds.size.height = still ? 8 : Self.barRest
            let wave = CABasicAnimation(keyPath: still ? "opacity" : "bounds.size.height")
            wave.fromValue = still ? 1 : Self.barRest
            wave.toValue = still ? 0.4 : 13
            wave.duration = still ? 0.6 : 0.3
            wave.autoreverses = true
            wave.repeatCount = .infinity
            wave.beginTime = now + Double(index) * (still ? 0 : 0.08)
            wave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wave.fillMode = .backwards
            bar.add(wave, forKey: "wave")
        }
        CATransaction.commit()
    }

    // The words landed: the bars give way to a check, then the pill leaves.
    func done() {
        guard let stage, let pill = bars.first?.superlayer else { return hide() }
        let current = generation
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.removeAnimation(forKey: "wave")
            Motion.basic(bar, "opacity", from: 1, to: 0, at: now, duration: 0.1)
            bar.opacity = 0
        }
        let cell: CGFloat = 2
        let mark = CALayer()
        mark.bounds = CGRect(x: 0, y: 0, width: CGFloat(Self.check[0].count) * cell, height: CGFloat(Self.check.count) * cell)
        mark.position = CGPoint(x: stage.bounds.midX, y: stage.bounds.midY)
        mark.contents = Pixels.image(Self.check, color: Pixels.ink)
        mark.magnificationFilter = .nearest
        pill.addSublayer(mark)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            Motion.spring(mark, "transform.scale", from: 0.3, to: 1, at: now + 0.05, omega: 20, zeta: 0.45)
        }
        Motion.basic(mark, "opacity", from: 0, to: 1, at: now + 0.05, duration: 0.1)
        CATransaction.commit()
        bars = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.generation == current else { return }
            self.hide()
        }
    }

    // Out: down toward the screen's edge.
    func hide() {
        guard let stage else { return }
        generation += 1
        let current = generation
        self.stage = nil
        bars = []
        working = false
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let timing = CAMediaTimingFunction(name: .easeIn)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            Motion.basic(stage, "transform.scale", from: 1, to: 0.85, at: now, duration: 0.16, timing: timing)
            Motion.basic(stage, "transform.translation.y", from: 0, to: -8, at: now, duration: 0.16, timing: timing)
            stage.transform = CATransform3DTranslate(CATransform3DMakeScale(0.85, 0.85, 1), 0, -8, 0)
        }
        Motion.basic(stage, "opacity", from: 1, to: 0, at: now, duration: 0.16, timing: timing)
        stage.opacity = 0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }
}
