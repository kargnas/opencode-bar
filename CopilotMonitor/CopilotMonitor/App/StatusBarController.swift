import AppKit
import SwiftUI
import ServiceManagement
import WebKit
import os.log

private let logger = Logger(subsystem: "com.copilotmonitor", category: "StatusBarController")

// MARK: - Refresh Interval
enum RefreshInterval: Int, CaseIterable {
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case thirtyMinutes = 1800
    
    var title: String {
        switch self {
        case .tenSeconds: return "10초"
        case .thirtySeconds: return "30초"
        case .oneMinute: return "1분"
        case .fiveMinutes: return "5분"
        case .thirtyMinutes: return "30분"
        }
    }
    
    static var defaultInterval: RefreshInterval { .thirtySeconds }
}

// MARK: - Status Bar Icon View
final class StatusBarIconView: NSView {
    private var percentage: Double = 0
    private var usedCount: Int = 0
    private var isLoading = false
    private var hasError = false
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 80, height: 22)
    }
    
    func update(used: Int, limit: Int) {
        usedCount = used
        percentage = limit > 0 ? min((Double(used) / Double(limit)) * 100, 100) : 0
        isLoading = false
        hasError = false
        needsDisplay = true
    }
    
    func showLoading() {
        isLoading = true
        needsDisplay = true
    }
    
    func showError() {
        hasError = true
        isLoading = false
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        drawCopilotIcon(at: NSPoint(x: 2, y: 3), size: 16, isDark: isDark)
        
        let progressRect = NSRect(x: 22, y: 7, width: 8, height: 8)
        drawCircularProgress(in: progressRect, isDark: isDark)
        
        drawUsageText(at: NSPoint(x: 34, y: 3), isDark: isDark)
    }
    
    private func drawCopilotIcon(at origin: NSPoint, size: CGFloat, isDark: Bool) {
        guard let icon = NSImage(named: "CopilotIcon") else { return }
        icon.isTemplate = true
        
        let tintedImage = NSImage(size: icon.size)
        tintedImage.lockFocus()
        NSColor.white.set()
        let imageRect = NSRect(origin: .zero, size: icon.size)
        imageRect.fill()
        icon.draw(in: imageRect, from: .zero, operation: .destinationIn, fraction: 1.0)
        tintedImage.unlockFocus()
        tintedImage.isTemplate = false
        
        let iconRect = NSRect(x: origin.x, y: origin.y, width: size, height: size)
        tintedImage.draw(in: iconRect)
    }
    
    private func drawCircularProgress(in rect: NSRect, isDark: Bool) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 0.5
        let lineWidth: CGFloat = 2
        
        NSColor.white.withAlphaComponent(0.2).setStroke()
        let bgPath = NSBezierPath()
        bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        bgPath.lineWidth = lineWidth
        bgPath.stroke()
        
        if isLoading {
            NSColor.white.withAlphaComponent(0.6).setStroke()
            let loadingPath = NSBezierPath()
            loadingPath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 180)
            loadingPath.lineWidth = lineWidth
            loadingPath.stroke()
            return
        }
        
        if hasError {
            NSColor.white.withAlphaComponent(0.6).setStroke()
            let errorPath = NSBezierPath()
            errorPath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 90, clockwise: true)
            errorPath.lineWidth = lineWidth
            errorPath.stroke()
            return
        }
        
        NSColor.white.setStroke()
        let endAngle = 90 - (360 * percentage / 100)
        let progressPath = NSBezierPath()
        progressPath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: CGFloat(endAngle), clockwise: true)
        progressPath.lineWidth = lineWidth
        progressPath.stroke()
    }
    
    private func drawUsageText(at origin: NSPoint, isDark: Bool) {
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
            .foregroundColor: NSColor.white
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attributes)
        attrString.draw(at: origin)
    }
    
    private func colorForPercentage(_ percentage: Double, isDark: Bool) -> NSColor {
        return NSColor.white
    }
}

// MARK: - Custom Usage View
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
        
        if usage.netBilledAmount > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            let costString = formatter.string(from: NSNumber(value: usage.netBilledAmount)) ?? String(format: "$%.2f", usage.netBilledAmount)
            costLabel.stringValue = "Add-on Cost: \(costString)"
            costLabel.textColor = .systemOrange
        } else {
            costLabel.stringValue = ""
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

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var statusBarIconView: StatusBarIconView!
    private var menu: NSMenu!
    private var usageItem: NSMenuItem!
    private var usageView: UsageMenuItemView!
    private var signInItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var refreshIntervalMenu: NSMenu!
    private var refreshTimer: Timer?
    
    private var currentUsage: CopilotUsage?
    private var lastFetchTime: Date?
    private var isFetching = false
    
    private var refreshInterval: RefreshInterval {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: "refreshInterval")
            return RefreshInterval(rawValue: rawValue) ?? .defaultInterval
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "refreshInterval")
            restartRefreshTimer()
            updateRefreshIntervalMenu()
        }
    }
    
    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
        setupNotificationObservers()
        startRefreshTimer()
        logger.info("init 완료")
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        statusBarIconView = StatusBarIconView(frame: NSRect(x: 0, y: 0, width: 70, height: 22))
        statusBarIconView.showLoading()
        statusItem.button?.addSubview(statusBarIconView)
        statusItem.button?.frame = statusBarIconView.frame
    }
    
    private func setupMenu() {
        menu = NSMenu()
        
        usageView = UsageMenuItemView(frame: NSRect(x: 0, y: 0, width: 220, height: 68))
        usageView.showLoading()
        usageItem = NSMenuItem()
        usageItem.view = usageView
        menu.addItem(usageItem)
        
        menu.addItem(NSMenuItem.separator())
        signInItem = NSMenuItem(title: "Sign In", action: #selector(signInClicked), keyEquivalent: "")
        signInItem.target = self
        menu.addItem(signInItem)
        
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let refreshIntervalItem = NSMenuItem(title: "Auto Refresh", action: nil, keyEquivalent: "")
        refreshIntervalMenu = NSMenu()
        for interval in RefreshInterval.allCases {
            let item = NSMenuItem(title: interval.title, action: #selector(refreshIntervalSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = interval.rawValue
            refreshIntervalMenu.addItem(item)
        }
        refreshIntervalItem.submenu = refreshIntervalMenu
        menu.addItem(refreshIntervalItem)
        updateRefreshIntervalMenu()
        
        let openBillingItem = NSMenuItem(title: "Open Billing", action: #selector(openBillingClicked), keyEquivalent: "b")
        openBillingItem.target = self
        menu.addItem(openBillingItem)
        
        menu.addItem(NSMenuItem.separator())
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(launchAtLoginClicked), keyEquivalent: "")
        launchAtLoginItem.target = self
        updateLaunchAtLoginState()
        menu.addItem(launchAtLoginItem)
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }
    
    private func updateRefreshIntervalMenu() {
        for item in refreshIntervalMenu.items {
            item.state = (item.tag == refreshInterval.rawValue) ? .on : .off
        }
    }
    
    @objc private func refreshIntervalSelected(_ sender: NSMenuItem) {
        if let interval = RefreshInterval(rawValue: sender.tag) {
            refreshInterval = interval
        }
    }
    
    private func restartRefreshTimer() {
        startRefreshTimer()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(forName: Notification.Name("billingPageLoaded"), object: nil, queue: .main) { [weak self] _ in
            logger.info("노티 수신: billingPageLoaded")
            Task { @MainActor in
                self?.fetchUsage()
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("sessionExpired"), object: nil, queue: .main) { [weak self] _ in
            logger.info("노티 수신: sessionExpired")
            Task { @MainActor in
                self?.updateUIForLoggedOut()
            }
        }
    }
    
    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        
        let interval = TimeInterval(refreshInterval.rawValue)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            logger.info("타이머 트리거 (\(self?.refreshInterval.title ?? ""))")
            Task { @MainActor in
                self?.triggerRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.triggerRefresh()
        }
    }
    
    func triggerRefresh() {
        logger.info("triggerRefresh 시작")
        AuthManager.shared.loadBillingPage()
    }
    
    private func fetchUsage() {
        logger.info("fetchUsage 시작, isFetching: \(self.isFetching)")
        guard !isFetching else { return }
        isFetching = true
        statusBarIconView.showLoading()
        usageView.showLoading()
        
        Task {
            let webView = AuthManager.shared.webView
            
            var customerId: String? = nil
            
            logger.info("fetchUsage: [Step 1] API(/api/v3/user)를 통한 ID 확보 시도")
            let userApiJS = """
            return await (async function() {
                try {
                    const response = await fetch('/api/v3/user', {
                        headers: { 'Accept': 'application/json' }
                    });
                    if (!response.ok) return JSON.stringify({ error: 'HTTP ' + response.status });
                    const data = await response.json();
                    return JSON.stringify(data);
                } catch (e) {
                    return JSON.stringify({ error: e.toString() });
                }
            })()
            """
            
            do {
                let result = try await webView.callAsyncJavaScript(userApiJS, arguments: [:], in: nil, contentWorld: .defaultClient)
                
                if let jsonString = result as? String,
                   let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? Int {
                    customerId = String(id)
                    logger.info("fetchUsage: API ID 확보 성공 - \(id)")
                }
            } catch {
                logger.error("fetchUsage: API 호출 중 에러 - \(error.localizedDescription)")
            }
            
            if customerId == nil {
                logger.info("fetchUsage: [Step 2] DOM 추출 시도")
                let extractionJS = """
                return (function() {
                    const el = document.querySelector('script[data-target="react-app.embeddedData"]');
                    if (el) {
                        try {
                            const data = JSON.parse(el.textContent);
                            if (data && data.payload && data.payload.customer && data.payload.customer.customerId) {
                                return data.payload.customer.customerId.toString();
                            }
                        } catch(e) {}
                    }
                    return null;
                })()
                """
                if let extracted = try? await evalJSONString(extractionJS, in: webView) {
                    customerId = extracted
                    logger.info("fetchUsage: DOM에서 customerId 추출 성공 - \(extracted)")
                }
            }
            
            if customerId == nil {
                logger.info("fetchUsage: [Step 3] HTML Regex 시도")
                do {
                    let htmlJS = "return document.documentElement.outerHTML"
                    if let html = try? await webView.callAsyncJavaScript(htmlJS, arguments: [:], in: nil, contentWorld: .defaultClient) as? String {
                        let patterns = [
                            #"customerId":(\d+)"#,
                            #"customerId&quot;:(\d+)"#,
                            #"customer_id=(\d+)"#,
                            #"data-customer-id="(\d+)""#
                        ]
                        for pattern in patterns {
                            if let regex = try? NSRegularExpression(pattern: pattern),
                               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                               let range = Range(match.range(at: 1), in: html) {
                                customerId = String(html[range])
                                logger.info("fetchUsage: HTML에서 ID 발견 - \(customerId!)")
                                break
                            }
                        }
                    }
                }
            }
            
            if let validCustomerId = customerId {
                let debugPath = "/Users/kargnas/copilot_debug.json"
                let cardJS = """
                return await (async function() {
                    try {
                        const res = await fetch('/settings/billing/copilot_usage_card?customer_id=\(validCustomerId)&period=3', {
                            headers: { 'Accept': 'application/json', 'x-requested-with': 'XMLHttpRequest' }
                        });
                        const text = await res.text();
                        try {
                            const json = JSON.parse(text);
                            // 디버깅을 위해 응답에 타임스탬프 추가
                            json._debug_timestamp = new Date().toISOString();
                            return json;
                        } catch (e) {
                            return { error: 'JSON Parse Error', body: text };
                        }
                    } catch(e) { return { error: e.toString() }; }
                })()
                """
                
                do {
                    let result = try await webView.callAsyncJavaScript(cardJS, arguments: [:], in: nil, contentWorld: .defaultClient)
                    
                    if let rootDict = result as? [String: Any] {
                        if let data = try? JSONSerialization.data(withJSONObject: rootDict, options: .prettyPrinted),
                           let jsonStr = String(data: data, encoding: .utf8) {
                            try? jsonStr.write(to: URL(fileURLWithPath: debugPath), atomically: true, encoding: .utf8)
                        }
                        
                        // 데이터가 payload나 data 안에 있을 수 있으므로 확인
                        var dict = rootDict
                        if let payload = rootDict["payload"] as? [String: Any] {
                            dict = payload
                        } else if let data = rootDict["data"] as? [String: Any] {
                            dict = data
                        }
                        
                        logger.info("fetchUsage: 데이터 파싱 시도 (Keys: \(dict.keys.joined(separator: ", ")))")
                        
                        let netBilledAmount = (dict["netBilledAmount"] as? Double) 
                            ?? (dict["net_billed_amount"] as? Double)
                            ?? (dict["netBilledAmount"] as? Int).map { Double($0) }
                            ?? 0.0
                            
                        let netQuantity = (dict["netQuantity"] as? Double) 
                            ?? (dict["net_quantity"] as? Double) 
                            ?? (dict["netQuantity"] as? Int).map { Double($0) }
                            ?? 0.0
                            
                        let discountQuantity = (dict["discountQuantity"] as? Double) 
                            ?? (dict["discount_quantity"] as? Double) 
                            ?? (dict["discountQuantity"] as? Int).map { Double($0) }
                            ?? 0.0
                        
                        // 한도(Limit) 파싱 - 여러 키 시도
                        let limit = (dict["userPremiumRequestEntitlement"] as? Int) 
                            ?? (dict["user_premium_request_entitlement"] as? Int) 
                            ?? (dict["userPremiumRequestEntitlement"] as? Double).map { Int($0) }
                            ?? (dict["user_premium_request_entitlement"] as? Double).map { Int($0) }
                            ?? (dict["quantity"] as? Int) 
                            ?? 0
                            
                        let filteredLimit = (dict["filteredUserPremiumRequestEntitlement"] as? Int) 
                            ?? (dict["filteredUserPremiumRequestEntitlement"] as? Double).map { Int($0) }
                            ?? 0
                        
                        let usage = CopilotUsage(
                            netBilledAmount: netBilledAmount,
                            netQuantity: netQuantity,
                            discountQuantity: discountQuantity,
                            userPremiumRequestEntitlement: limit,
                            filteredUserPremiumRequestEntitlement: filteredLimit
                        )
                        
                        self.currentUsage = usage
                        self.lastFetchTime = Date()
                        self.updateUIForSuccess(usage: usage)
                        self.saveCache(usage: usage)
                        self.isFetching = false
                        logger.info("fetchUsage: 성공")
                        return
                    }
                } catch {
                    let errorMsg = "JS Error: \(error.localizedDescription)"
                    try? errorMsg.write(to: URL(fileURLWithPath: debugPath), atomically: true, encoding: .utf8)
                }
            }
            
            if let cached = loadCache() {
                self.updateUIForSuccess(usage: cached.usage)
                self.isFetching = false
            } else {
                self.handleFetchError(UsageFetcherError.noUsageData)
                self.isFetching = false
            }
        }
    }
    
    private func evalJSONString(_ js: String, in webView: WKWebView) async throws -> String {
        let result = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .defaultClient)
        
        if let json = result as? String {
            return json
        } else if let dict = result as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let json = String(data: data, encoding: .utf8) {
            return json
        } else {
            throw UsageFetcherError.invalidJSResult
        }
    }
    
    private func updateUIForSuccess(usage: CopilotUsage) {
        statusBarIconView.update(used: usage.usedRequests, limit: usage.limitRequests)
        usageView.update(usage: usage)
        signInItem.isHidden = true
    }
    
    private func updateUIForLoggedOut() {
        statusBarIconView.showError()
        usageView.showError("로그인 필요")
        signInItem.isHidden = false
    }
    
    private func handleFetchError(_ error: Error) {
        statusBarIconView.showError()
        usageView.showError("Update Failed")
    }
    
    @objc private func signInClicked() {
        NotificationCenter.default.post(name: Notification.Name("sessionExpired"), object: nil)
    }
    
    @objc private func refreshClicked() {
        triggerRefresh()
    }
    
    @objc private func openBillingClicked() {
        if let url = URL(string: "https://github.com/settings/billing/premium_requests_usage") { NSWorkspace.shared.open(url) }
    }
    
    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
    
    @objc private func launchAtLoginClicked() {
        let service = SMAppService.mainApp
        try? (service.status == .enabled ? service.unregister() : service.register())
        updateLaunchAtLoginState()
    }
    
    private func updateLaunchAtLoginState() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    
    private func saveCache(usage: CopilotUsage) {
        if let data = try? JSONEncoder().encode(CachedUsage(usage: usage, timestamp: Date())) {
            UserDefaults.standard.set(data, forKey: "copilot.usage.cache")
        }
    }
    
    private func loadCache() -> CachedUsage? {
        guard let data = UserDefaults.standard.data(forKey: "copilot.usage.cache") else { return nil }
        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }
}

enum UsageFetcherError: LocalizedError {
    case noCustomerId
    case noUsageData
    case invalidJSResult
    case parsingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noCustomerId: return "Customer ID를 찾을 수 없습니다"
        case .noUsageData: return "사용량 데이터를 찾을 수 없습니다"
        case .invalidJSResult: return "JS 결과가 올바르지 않습니다"
        case .parsingFailed(let msg): return "파싱 실패: \(msg)"
        }
    }
}

// MARK: - Models (Local Definition to fix scope issues)
struct CopilotUsage: Codable {
    let netBilledAmount: Double
    let netQuantity: Double
    let discountQuantity: Double
    let userPremiumRequestEntitlement: Int
    let filteredUserPremiumRequestEntitlement: Int
    
    init(netBilledAmount: Double, netQuantity: Double, discountQuantity: Double, userPremiumRequestEntitlement: Int, filteredUserPremiumRequestEntitlement: Int) {
        self.netBilledAmount = netBilledAmount
        self.netQuantity = netQuantity
        self.discountQuantity = discountQuantity
        self.userPremiumRequestEntitlement = userPremiumRequestEntitlement
        self.filteredUserPremiumRequestEntitlement = filteredUserPremiumRequestEntitlement
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        netBilledAmount = (try? container.decodeIfPresent(Double.self, forKey: .netBilledAmount)) ?? 0.0
        netQuantity = (try? container.decodeIfPresent(Double.self, forKey: .netQuantity)) ?? 0.0
        discountQuantity = (try? container.decodeIfPresent(Double.self, forKey: .discountQuantity)) ?? 0.0
        userPremiumRequestEntitlement = (try? container.decodeIfPresent(Int.self, forKey: .userPremiumRequestEntitlement)) ?? 0
        filteredUserPremiumRequestEntitlement = (try? container.decodeIfPresent(Int.self, forKey: .filteredUserPremiumRequestEntitlement)) ?? 0
    }
    
    var usedRequests: Int { return Int(discountQuantity) }
    var limitRequests: Int { return userPremiumRequestEntitlement }
    var usagePercentage: Double {
        guard limitRequests > 0 else { return 0 }
        return (Double(usedRequests) / Double(limitRequests)) * 100
    }
}

struct CachedUsage: Codable {
    let usage: CopilotUsage
    let timestamp: Date
}
