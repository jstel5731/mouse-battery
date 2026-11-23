import AppKit

/// Draws the menu bar icon: a mouse lying on its side, filled like the macOS battery icon,
/// with the percentage cut out of the body.
enum BatteryIcon {
    private static let size = NSSize(width: 31, height: 14)
    private static let backRadius: CGFloat = 7
    private static let frontRadius: CGFloat = 5.5
    private static let buttonSplitLength: CGFloat = 6
    private static let emptyAlpha: CGFloat = 0.4

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

        let split = NSBezierPath()
        split.move(to: NSPoint(x: size.width, y: size.height / 2))
        split.line(to: NSPoint(x: size.width - buttonSplitLength, y: size.height / 2))
        split.lineWidth = 1
        split.stroke()

        drawLabel(percent.map(String.init) ?? "–", charging: charging)
    }

    /// Top view of a mouse pointing right: a wide palm rest on the left, narrower buttons on the right.
    private static func bodyPath() -> NSBezierPath {
        let midY = size.height / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: backRadius, y: 0))
        path.line(to: NSPoint(x: size.width - frontRadius, y: midY - frontRadius))
        path.appendArc(withCenter: NSPoint(x: size.width - frontRadius, y: midY),
                       radius: frontRadius, startAngle: -90, endAngle: 90)
        path.line(to: NSPoint(x: backRadius, y: size.height))
        path.appendArc(withCenter: NSPoint(x: backRadius, y: midY),
                       radius: backRadius, startAngle: 90, endAngle: 270)
        path.close()
        return path
    }

    private static func drawLabel(_ text: String, charging: Bool) {
        // Three digits need a smaller font to stay clear of the button split.
        let fontSize: CGFloat = text.count < 3 ? 10 : charging ? 7.5 : 8.5
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.black,
        ])
        let textSize = label.size()

        let bolt = charging ? boltImage(pointSize: fontSize - 1.5) : nil
        let boltWidth = bolt.map { $0.size.width + 0.5 } ?? 0

        let labelArea = NSRect(x: 2, y: 0, width: size.width - buttonSplitLength - 3, height: size.height)
        var x = labelArea.midX - (textSize.width + boltWidth) / 2
        label.draw(at: NSPoint(x: x, y: labelArea.midY - textSize.height / 2))

        if let bolt {
            x += textSize.width + 0.5
            let rect = NSRect(x: x, y: labelArea.midY - bolt.size.height / 2,
                              width: bolt.size.width, height: bolt.size.height)
            bolt.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
        }
    }

    private static func boltImage(pointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}
