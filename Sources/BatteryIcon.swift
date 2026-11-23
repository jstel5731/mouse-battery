import AppKit

/// Draws the menu bar icon: the top view of a Pro X Superlight lying on its side (buttons to the
/// right), filled like the macOS battery icon, with the percentage cut out of the palm rest.
enum BatteryIcon {
    // MARK: - Tweakable appearance

    /// Thickness of the percentage digits: .regular, .medium, .semibold, .bold, .heavy or .black.
    private static let labelWeight: NSFont.Weight = .semibold
    /// Digit size in points for one or two digits, and for "100".
    private static let labelFontSize: CGFloat = 9.5
    private static let labelFontSizeThreeDigits: CGFloat = 7.5
    /// Opacity of the part of the body that is not filled by the battery level.
    private static let emptyAlpha: CGFloat = 0.4

    // MARK: - Geometry (points; x runs from the back of the mouse to the front)

    private static let size = NSSize(width: 27, height: 15)
    private static let midY = size.height / 2
    /// The body is widest here, under the palm.
    private static let widestX: CGFloat = 8.5
    private static let frontHalfHeight: CGFloat = 6
    /// Where the two buttons end and the palm rest begins.
    private static let buttonEdgeX: CGFloat = 16.5
    private static let wheelCenterX: CGFloat = 21.5

    /// - Parameter percent: nil when no reading is available yet.
    static func image(percent: Int?, charging: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(percent: percent, charging: charging)
            return true
        }
        // A template image lets macOS tint it for light and dark menu bars.
        image.isTemplate = true
        return image
    }

    private static func draw(percent: Int?, charging: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let body = bodyPath()

        NSColor.black.withAlphaComponent(emptyAlpha).setFill()
        body.fill()

        if let percent {
            let level = CGFloat(min(max(percent, 0), 100)) / 100
            context.saveGState()
            body.addClip()
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: size.width * level, height: size.height).fill()
            context.restoreGState()
        }

        // Everything below is erased from the body instead of painted on top of it.
        context.setBlendMode(.destinationOut)
        NSColor.black.set()

        drawButtonEdge()
        if charging {
            drawBolt()
        } else {
            drawButtonSplitAndWheel()
        }
        drawLabel(percent.map(String.init) ?? "–")
    }

    /// Outline of the mouse: a blunt front, sides that flare out towards the palm, a round back.
    private static func bodyPath() -> NSBezierPath {
        let halfHeight = size.height / 2
        let shoulderX = size.width - 3.5

        func point(_ x: CGFloat, _ offset: CGFloat) -> NSPoint { NSPoint(x: x, y: midY + offset) }

        let path = NSBezierPath()
        path.move(to: point(0, 0))
        for side: CGFloat in [1, -1] {
            let back = [point(0, 0), point(0, side * 4.6), point(3.6, side * halfHeight), point(widestX, side * halfHeight)]
            let flank = [point(14, side * halfHeight), point(shoulderX - 5, side * frontHalfHeight),
                         point(shoulderX, side * frontHalfHeight)]
            let front = [point(size.width - 1, side * frontHalfHeight), point(size.width, side * 3.4),
                         point(size.width, 0)]
            if side == 1 {
                path.curve(to: back[3], controlPoint1: back[1], controlPoint2: back[2])
                path.curve(to: flank[2], controlPoint1: flank[0], controlPoint2: flank[1])
                path.curve(to: front[2], controlPoint1: front[0], controlPoint2: front[1])
            } else {
                // The lower half runs back from the front, so the same curves are traced in reverse.
                path.curve(to: flank[2], controlPoint1: front[1], controlPoint2: front[0])
                path.curve(to: back[3], controlPoint1: flank[1], controlPoint2: flank[0])
                path.curve(to: back[0], controlPoint1: back[2], controlPoint2: back[1])
            }
        }
        path.close()
        return path
    }

    /// The curved seam between the buttons and the palm rest.
    private static func drawButtonEdge() {
        let reach = size.height / 2 + 1
        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: buttonEdgeX + 1.2, y: midY - reach))
        edge.curve(to: NSPoint(x: buttonEdgeX + 1.2, y: midY + reach),
                   controlPoint1: NSPoint(x: buttonEdgeX - 0.6, y: midY - 3),
                   controlPoint2: NSPoint(x: buttonEdgeX - 0.6, y: midY + 3))
        edge.lineWidth = 0.75
        edge.stroke()
    }

    private static func drawButtonSplitAndWheel() {
        let split = NSBezierPath()
        split.move(to: NSPoint(x: buttonEdgeX, y: midY))
        split.line(to: NSPoint(x: size.width, y: midY))
        split.lineWidth = 0.75
        split.stroke()

        let wheel = NSRect(x: wheelCenterX - 2.25, y: midY - 1.25, width: 4.5, height: 2.5)
        NSBezierPath(roundedRect: wheel, xRadius: 1.25, yRadius: 1.25).fill()
    }

    /// While charging, a bolt takes the place of the scroll wheel.
    private static func drawBolt() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 7.5, weight: .bold)
        guard let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let rect = NSRect(x: wheelCenterX + 0.25 - bolt.size.width / 2, y: midY - bolt.size.height / 2,
                          width: bolt.size.width, height: bolt.size.height)
        bolt.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
    }

    private static func drawLabel(_ text: String) {
        let fontSize = text.count >= 3 ? labelFontSizeThreeDigits : labelFontSize
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: labelWeight),
            .foregroundColor: NSColor.black,
        ])
        let textSize = label.size()
        let palmCenterX = (1 + buttonEdgeX) / 2
        label.draw(at: NSPoint(x: palmCenterX - textSize.width / 2, y: midY - textSize.height / 2))
    }
}
