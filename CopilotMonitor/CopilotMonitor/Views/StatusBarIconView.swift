import AppKit

// MARK: - Status Bar Icon View
final class StatusBarIconView: NSView {
    private var percentage: Double = 0
    private var usedCount: Int = 0
    private var addOnCost: Double = 0
    private var isLoading = false
    private var hasError = false
    
    private var textColor: NSColor {
        guard let button = self.superview as? NSStatusBarButton else {
            return .white
        }
        return button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }
    
    /// Dynamic width calculation based on content
    /// - Copilot icon (16px) + padding (6px) = 22px base
    /// - With add-on cost: icon + cost text width
    /// - Without add-on cost: icon + circle (8px) + padding (4px) + number text width
    override var intrinsicContentSize: NSSize {
        let baseIconWidth: CGFloat = 22 // icon (16) + right padding (6)
        
        if addOnCost > 0 {
            // Calculate cost text width dynamically
            let costText = formatCost(addOnCost)
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let textWidth = (costText as NSString).size(withAttributes: [.font: font]).width
            return NSSize(width: baseIconWidth + textWidth + 4, height: 23)
        } else {
            // Circle (8px) + padding (4px) + number text width
            let text = isLoading ? "..." : (hasError ? "Err" : "\(usedCount)")
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            return NSSize(width: baseIconWidth + 8 + 4 + textWidth + 4, height: 23)
        }
    }
    
    func update(used: Int, limit: Int, cost: Double = 0) {
        usedCount = used
        addOnCost = cost
        percentage = limit > 0 ? min((Double(used) / Double(limit)) * 100, 100) : 0
        isLoading = false
        hasError = false
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    func showLoading() {
        isLoading = true
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    func showError() {
        hasError = true
        isLoading = false
        addOnCost = 0  // Reset add-on cost to hide dollar sign
        usedCount = 0
        percentage = 0
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let color = textColor
        let yOffset: CGFloat = 4
        
        drawCopilotIcon(at: NSPoint(x: 2, y: yOffset), size: 16, color: color)
        
        if addOnCost > 0 {
            drawCostText(at: NSPoint(x: 22, y: yOffset), color: color)
        } else {
            let progressRect = NSRect(x: 22, y: yOffset + 4, width: 8, height: 8)
            drawCircularProgress(in: progressRect, color: color)
            drawUsageText(at: NSPoint(x: 34, y: yOffset), color: color)
        }
    }
    
    private func drawCopilotIcon(at origin: NSPoint, size: CGFloat, color: NSColor) {
        guard let icon = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Usage") else { return }
        icon.isTemplate = true
        
        let tintedImage = NSImage(size: icon.size)
        tintedImage.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: icon.size)
        imageRect.fill()
        icon.draw(in: imageRect, from: .zero, operation: .destinationIn, fraction: 1.0)
        tintedImage.unlockFocus()
        tintedImage.isTemplate = false
        
        let iconRect = NSRect(x: origin.x, y: origin.y, width: size, height: size)
        tintedImage.draw(in: iconRect)
    }
    
    private func drawCircularProgress(in rect: NSRect, color: NSColor) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 0.5
        let lineWidth: CGFloat = 2
        
        color.withAlphaComponent(0.2).setStroke()
        let bgPath = NSBezierPath()
        bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        bgPath.lineWidth = lineWidth
        bgPath.stroke()
        
        if isLoading {
            color.withAlphaComponent(0.6).setStroke()
            let loadingPath = NSBezierPath()
            loadingPath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 180)
            loadingPath.lineWidth = lineWidth
            loadingPath.stroke()
            return
        }
        
        if hasError {
            color.withAlphaComponent(0.6).setStroke()
            let errorPath = NSBezierPath()
            errorPath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 90, clockwise: true)
            errorPath.lineWidth = lineWidth
            errorPath.stroke()
            return
        }
        
        color.setStroke()
        let endAngle = 90 - (360 * percentage / 100)
        let progressPath = NSBezierPath()
        progressPath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: CGFloat(endAngle), clockwise: true)
        progressPath.lineWidth = lineWidth
        progressPath.stroke()
    }
    
    private func drawUsageText(at origin: NSPoint, color: NSColor) {
        let text: String
        
        if isLoading {
            text = "..."
        } else if hasError {
            text = "Err"
        } else {
            text = "\(usedCount)"
        }
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attributes)
        attrString.draw(at: origin)
    }
    
    private func drawCostText(at origin: NSPoint, color: NSColor) {
        let text = formatCost(addOnCost)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        attrString.draw(at: origin)
    }
    
    private func formatCost(_ cost: Double) -> String {
        if cost >= 10 {
            return String(format: "$%.1f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }
    
    private func colorForPercentage(_ percentage: Double) -> NSColor {
        return NSColor.white
    }
}
