import AppKit
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "UsageMenuItemView")

final class UsageMenuItemView: NSView {
    private let progressBar: NSView
    private let progressFill: NSView
    private let usageLabel: NSTextField
    private let percentLabel: NSTextField
    private let costLabel: NSTextField
    
    private var fillWidthConstraint: NSLayoutConstraint?
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 220, height: 68)
    }
    
    override init(frame frameRect: NSRect) {
        progressBar = NSView()
        progressFill = NSView()
        usageLabel = NSTextField(labelWithString: "")
        percentLabel = NSTextField(labelWithString: "")
        costLabel = NSTextField(labelWithString: "")
        
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        usageLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        usageLabel.textColor = .labelColor
        usageLabel.alignment = .left
        usageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(usageLabel)
        
        percentLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(percentLabel)
        
        progressBar.wantsLayer = true
        progressBar.layer?.cornerRadius = 4
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressBar)
        
        progressFill.wantsLayer = true
        progressFill.layer?.cornerRadius = 3
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressBar.addSubview(progressFill)
        
        costLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        costLabel.textColor = .secondaryLabelColor
        costLabel.alignment = .right
        costLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(costLabel)
        
        updateColors()
        
        NSLayoutConstraint.activate([
            usageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            usageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            
            percentLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            percentLabel.leadingAnchor.constraint(greaterThanOrEqualTo: usageLabel.trailingAnchor, constant: 8),
            
            progressBar.topAnchor.constraint(equalTo: usageLabel.bottomAnchor, constant: 6),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            progressBar.heightAnchor.constraint(equalToConstant: 8),
            
            progressFill.topAnchor.constraint(equalTo: progressBar.topAnchor, constant: 1),
            progressFill.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: -1),
            progressFill.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor, constant: 1),
            
            costLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 6),
            costLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            costLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
            costLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        
        fillWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)
        fillWidthConstraint?.isActive = true
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    
    private func updateColors() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        progressBar.layer?.backgroundColor = (isDark ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.08)).cgColor
    }
    
    static func colorForPercentage(_ percentage: Double) -> NSColor {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch percentage {
        case 0..<50:
            return isDark ? NSColor.systemGreen.withAlphaComponent(0.9) : NSColor.systemGreen
        case 50..<75:
            return isDark ? NSColor.systemYellow.withAlphaComponent(0.95) : NSColor.systemYellow.blended(withFraction: 0.3, of: .systemOrange) ?? .systemYellow
        case 75..<90:
            return isDark ? NSColor.systemOrange : NSColor.systemOrange.blended(withFraction: 0.2, of: .systemRed) ?? .systemOrange
        default:
            return NSColor.systemRed
        }
    }
    
    func update(usage: CopilotUsage) {
        let used = usage.usedRequests
        let limit = usage.limitRequests
        let percentage = limit > 0 ? min((Double(used) / Double(limit)) * 100, 100) : 0
        
        usageLabel.stringValue = "Used: \(used.formatted()) / \(limit.formatted())"
        percentLabel.stringValue = "\(Int(percentage))%"
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let costString = formatter.string(from: NSNumber(value: usage.netBilledAmount)) ?? String(format: "$%.2f", usage.netBilledAmount)
        costLabel.stringValue = "Add-on Cost: \(costString)"
        
        if usage.netBilledAmount > 0 {
            costLabel.textColor = .systemOrange
        } else {
            costLabel.textColor = .secondaryLabelColor
        }
        
        let color = Self.colorForPercentage(percentage)
        progressFill.layer?.backgroundColor = color.cgColor
        percentLabel.textColor = color
        
        layoutSubtreeIfNeeded()
        let barWidth = progressBar.bounds.width - 2
        let fillWidth = barWidth * CGFloat(percentage / 100)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            self.fillWidthConstraint?.constant = max(fillWidth, 0)
            self.layoutSubtreeIfNeeded()
        }
    }
    
    func showLoading() {
        usageLabel.stringValue = "Loading..."
        percentLabel.stringValue = ""
        costLabel.stringValue = ""
        progressFill.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        fillWidthConstraint?.constant = 40
    }
    
    func showError(_ message: String) {
        usageLabel.stringValue = message
        percentLabel.stringValue = "⚠️"
        costLabel.stringValue = ""
        percentLabel.textColor = .systemOrange
        progressFill.layer?.backgroundColor = NSColor.systemOrange.cgColor
        fillWidthConstraint?.constant = 0
    }
}
