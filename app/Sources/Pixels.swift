import CoreGraphics

// Koe's pixel art and colors, shared by the menu bar item, the toast and the
// app icon (docs/brand.md). Sprites are drawn one cell per pixel and scaled up
// without smoothing.
enum Pixels {
    // The bubble, the kind you send: three corners round, the bottom right
    // one square. Eyes and mouth are cut out of the ink.
    private static let top = ["..#######..", ".#########.", "###########", "###.###.###", "###########"]
    private static let bottom = ["###########", ".##########", "..#########", "..........."]

    static let ready = top + ["###########", "####...####"] + bottom
    static let listening = top + ["####...####", "####...####"] + bottom
    static let typed = top + ["###.###.###", "####...####"] + bottom

    // An update waiting, in the menu's update row: Wham's dot.
    static let dot = [".####.", "######", "######", "######", "######", ".####."]

    // The sprite's cells as squares of `cell` points, from `origin` (bottom left).
    static func path(_ rows: [String], origin: CGPoint, cell: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        for (y, row) in rows.enumerated() {
            for (x, char) in row.enumerated() where char == "#" {
                path.addRect(CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(rows.count - 1 - y) * cell, width: cell, height: cell))
            }
        }
        return path
    }

    static func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    static let ink = srgb(0x1a0b17)
    static let butter = srgb(0xfff1b8)
    static let blush = srgb(0xff8fc8)
    // Bubblegum, cherry, violet: the voice and the evening.
    static let candy = [srgb(0xff6fae), srgb(0xff7a7a), srgb(0xb07bff)]
    static let glow = srgb(0xff50a0)

    // The sprite at one pixel per cell, in one color.
    static func image(_ rows: [String], color: CGColor) -> CGImage? {
        let height = rows.count, width = rows.map(\.count).max() ?? 0
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(color)
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() where cell == "#" {
                context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
            }
        }
        return context.makeImage()
    }

    // The sprite with `scale` device pixels per cell, for the menu bar.
    static func image(_ rows: [String], color: CGColor, scale: Int) -> CGImage? {
        guard let small = image(rows, color: color) else { return nil }
        let width = small.width * scale, height = small.height * scale
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(small, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
