## Language
- All of comments in code base, commit message, PR content and title should be written in English.
  - If you find any Korean text, please translate it to English.
- **UI Language**: All user-facing text in the app MUST be in English.

## UI Styling Rules
- **No colors for text emphasis**: Do NOT use `NSColor` attributes like `.foregroundColor` for menu items or labels.
- **Use instead**:
  - **Bold**: `NSFont.boldSystemFont(ofSize:)` for important text
  - **Underline**: `.underlineStyle: NSUnderlineStyle.single.rawValue` for critical warnings
  - **SF Symbols**: Use `NSImage(systemSymbolName:accessibilityDescription:)` for menu item icons
- **Do NOT use**:
  - **Emoji**: Never use emoji for menu item icons. Always use SF Symbols instead.
- **Exception**: Progress bars and status indicators can use color (green/yellow/orange/red).

## Requirements
- Get the data from API only, not from DOM.
- Get useful session information (cookie, bearer and etc) from DOM/HTML if needed.
- Login should be webview and ask to the user to login.

## Reference
- Copilot Usage (HTML)
  - https://github.com/settings/billing/premium_requests_usage

## Instruction
- Always compile and run again after each change, and then ask to the user to see it. (Kill the existing process before running)

## How to get quota usage?
- in `@/scripts/` directory, you can see all of the scripts for every providers to get quota usage.

## Release Policy
- **Workflow**: STRICTLY follow `docs/RELEASE_WORKFLOW.md` for versioning, building, signing, and notarizing.
- **Signing**: All DMGs distributed via GitHub Releases **MUST** be signed with Developer ID and **NOTARIZED** to pass macOS Gatekeeper.
- **Documentation**: Update `README.md` and screenshots if UI changes significantly before release.

  <!-- opencode:reflection:start -->
### Error Handling & API Fallbacks
- **API Response Type Flexibility**: External APIs may return different types than expected
  - Numeric Fields Can Be Strings: Fields like `balance` may come as String instead of Double/Int
  - Optional Fields May Vary: Some providers return fields that others don't (e.g., `reset_at`, `limit_window_seconds`)
  - Pattern: Add computed properties for type conversion (e.g., `balanceAsDouble` converts String to Double)
  - Example Fix: Codex `balance` returned as String, added `balanceAsDouble` computed property for conversion
- **NSNumber Type Handling**: API responses may return `NSNumber` instead of `Int` or `Double`
   - Always check for `NSNumber` type when parsing numeric values from API responses
   - Pattern: `value as? NSNumber` → `doubleValue`/`intValue`
   - Example failure: Cost showing wrong value due to missing NSNumber handling
- **Menu Bar App (LSUIElement) Special Requirements**:
  - UI Display: Must call `NSApp.activate(ignoringOtherApps: true)` before showing update dialogs
  - Target Assignment: Menu item targets must be explicitly set to `NSApp.delegate` (not `self`)
  - Window Management: Close blank Settings windows on app launch
 - **Swift Concurrency & Actor Isolation**:
   - Task Capture: Always use `[weak self]` in Task blocks to avoid retain cycles
   - MainActor: Use `@MainActor [weak self]` pattern when updating UI from async contexts
   - Pre-compute Values: Cache values like `refreshInterval.title` before closures to avoid actor isolation issues
   - NotificationCenter Pattern: Use `guard let self = self else { return }` before Task, then `[weak self]` in Task capture list
- **Usage Calculation Completeness**:
  - Total Requests: Always sum both `includedRequests` AND `billedRequests` for accurate predictions
  - Prediction Algorithms: Use `totalRequests` (not just `included`) for weighted average calculations
  - UI Display: Show total requests in daily usage breakdown, not just included
 - **DMG Packaging Cleanliness**:
   - Staging Directory: Create clean staging dir containing ONLY app bundle and Applications symlink
   - Exclude Files: Prevent `Packaging.log`, `DistributionSummary.plist`, and other Xcode artifacts from DMG
   - Pattern: `mkdir -p staging; cp -R app.app staging/; ln -s /Applications staging/`
 - **DerivedData Path Handling**:
   - Wildcard Warning: Path `~/Library/Developer/Xcode/DerivedData/CopilotMonitor-*/Build/Products/Debug/OpencodeProvidersMonitor.app` may break if multiple DerivedData directories exist
   - Solution: Use `xcodebuild -showBuildSettings | grep BUILT_PRODUCTS_DIR` to get exact path, or open using `open` which finds the latest build
  - **Provider Type Classification**:
   - API Structure Determines Type: Provider billing model must match API response structure
   - Quota-based Indicators: `used_percent`, `remaining`, `entitlement` fields indicate quota-based model
   - Pay-as-you-go Indicators: `credits`, `usage`, `utilization` fields indicate pay-as-you-go model
   - Example Fix: Codex initially classified as pay-as-you-go, but API returns `used_percent` → corrected to quota-based
   - Test Alignment: When fixing provider type, update corresponding tests to match new implementation
 - **Menu Bar Item Lifecycle Management**:
   - Hidden Items Keep Objects Alive: Use `isHidden = true` instead of commenting out to prevent nil reference crashes
   - Implicitly Unwrapped Optionals: `NSMenuItem!` properties require initialization even if hidden from UI
   - Example Failure: Commenting out menu items causes crashes when validation logic still references them
   - Pattern: Always initialize menu items that may be referenced elsewhere, control visibility via `isHidden`
- **Language Policy Enforcement**:
   - All Log Messages Must Be English: Including debug logs, error messages, and informational logging
   - Pattern: After code changes, review log messages for Korean text and translate to English
   - Example: "fetchUsage 시작" → "fetchUsage started", "API ID 확보 성공" → "API ID obtained successfully"
   - Reference: AGENTS.md Language section requires all code comments, logs, and messages to be in English
- **Debug Code Cleanup**:
   - Remove Development Logging Before Commits: File-based debug logging (`/tmp/*.log`) should be removed after troubleshooting
   - Debug Pattern: File I/O for debugging should use `#if DEBUG` guard or be removed entirely
   - Example: Removed 110 lines of debug logging from `fetchMultiProviderData()` and `updateMultiProviderMenu()` after multi-provider feature stabilized
   - Pattern: Production code should only use structured logging (`os.log`/`Logger`), not ad-hoc file writing
  - **Access Modifier Awareness During Refactoring**:
     - Internal Access for Cross-Module Dependencies: Properties needed by external classes may need broader access (e.g., `var` instead of `private var`)
     - Example: `predictionPeriodMenu` changed from `private var` to `var` when `createCopilotHistorySubmenu()` moved to separate builder
     - Example: `getHistoryUIState()` changed from `private func` to `func` when accessed from external menu builders
     - Pattern: When extracting code to separate files, verify access modifiers still allow required dependencies
     - **Process.waitUntilExit() Blocking Issue**:
        - Synchronous Blocking: `Process.waitUntilExit()` is a blocking call even in async contexts
        - Multi-Provider Impact: Blocking providers prevent other providers from completing fetch operations
        - Async Solution: Use `withCheckedThrowingContinuation` with `terminationHandler` and `readabilityHandler` for non-blocking process execution
        - Example: AntigravityProvider uses `runCommandAsync()` wrapper; OpenCodeZenProvider uses `withCheckedThrowingContinuation` pattern
        - Pattern: Replace `waitUntilExit()` with async closure-based APIs using Process.terminationHandler and Pipe.readabilityHandler
        - Parallel Fetching Enables: Once processes are non-blocking, all providers can fetch in parallel efficiently
  - **Menu Rebuild Strategy**:
     - Tag-Based Item Removal: Use unique tags (e.g., tag 999) for dynamically generated menu items
     - Clean Rebuild Pattern: Remove all items with specific tag, then rebuild menu section from scratch
     - Separation of Concerns: Static menu items (tag 0) vs dynamic provider items (tag 999)
     - Example: `menu.items.removeAll(where: { $0.tag == 999 })` clears old provider data before fresh rebuild
     - Pattern: Tag-based filtering ensures clean menu updates without duplicating items
   - **CI/CD Build Strategy**:
     - Export Archive Failure: `xcodebuild -exportArchive` can fail in CI environments with signing issues
     - Direct Copy Solution: Use `cp -R` to copy app bundle from archive directly instead of exportArchive for unsigned builds
     - Pattern: For unsigned builds in CI, copy from `build/*.xcarchive/Products/Applications/*.app` to export directory
     - Code Signing Style: Set `CODE_SIGN_STYLE=Manual` in CI to prevent automatic signing conflicts
     - Sparkle Signature Parsing: Use `awk -F '"' '{print $2}'` to extract signature from sign_update output
     - Example Fix: Changed from exportArchive to direct copy to resolve CI build failures
   - **App Name Consistency Across Scripts**:
      - Build Scripts Must Match: App name changes require updates to pkill commands, DerivedData paths, and workflow files
      - Example: Changed from `CopilotMonitor` to `OpencodeProvidersMonitor` required updating:
        - `pkill -x CopilotMonitor` → `pkill -x OpencodeProvidersMonitor`
        - `~/Library/Developer/Xcode/DerivedData/CopilotMonitor-*/Build/Products/Debug/CopilotMonitor.app` → `OpencodeProvidersMonitor.app`
        - `.xcarchive`, `.app` bundle names in workflow files
      - Pattern: When renaming app, search all build scripts, workflows, and documentation for old name references
   - **Provider Data Ordering**:
       - API Returns Unordered Data: Dictionary iteration order is not guaranteed in Swift
       - Menu Display Issue: Provider items appearing in different order on each refresh cycle
       - Root Cause: Looping over `[ProviderIdentifier: ProviderResult]` dictionary without explicit ordering
       - Solution: Create explicit display order array or use sorted keys when iterating
       - Example: `let providerDisplayOrder = ["open_code_zen", "gemini_cli", "claude", "open_router", "antigravity"]`
       - Pattern: Define display order independently of data source to maintain consistent UI
     - **Menu Item Reference Deadlock**:
        - Shared NSMenuItem Reference: Referencing the same NSMenuItem instance (like `predictionPeriodMenu`) from multiple submenus can cause deadlocks
        - Manifestation: Menu becomes unresponsive or hangs when clicking on submenu items
        - Root Cause: NSMenuItem is not thread-safe when shared across different menu hierarchies
        - Solution: Always create fresh NSMenu instances for dynamically generated submenus instead of reusing shared references
        - Example Failure: `predictionPeriodMenu.submenu = predictionPeriodMenu` caused deadlock in history submenu
        - Fix: Create new `let periodSubmenu = NSMenu()` and rebuild contents instead of referencing existing menu
        - Pattern: Use constructor pattern to create independent menu objects for each submenu instance
   - **Loading State Management in Parallel Async Operations**:
      - Parallel Provider Fetching: All providers should fetch in parallel to minimize total fetch time
      - Loading State Tracking: Use `Set<ProviderIdentifier>` to track providers currently fetching
      - Pre-Fetch Menu Update: Update menu before starting fetch to show "Loading..." state
      - Post-Fetch Menu Update: Remove loading state and replace with actual data after fetch completes
      - Loading Item Styling: Show "Loading..." text with disabled `isEnabled = false` state
      - Pattern: `loadingProviders.insert(identifier)` → `updateMenu()` → await fetch → `loadingProviders.remove(identifier)` → `updateMenu()`
    - **Daily History Cache Strategy**:
       - Hybrid Approach: Fetch fresh data for recent days (today/yesterday), serve older data from cache
       - Timeout Risk Reduction: Reduce external CLI/API calls significantly (e.g., 7 calls → 2 calls = 71% reduction)
       - UserDefaults Cache: Use Codable structures with JSON encoding for simple persistence
       - Cache Validation: Check date before using cached data to avoid stale information
       - Sequential Internal Loading: Each provider can load history day-by-day sequentially with caching making it acceptable
       - Pattern: Load cache → fetch recent → merge → save updated cache
    - **Multiline Text Handling in Custom Views**:
       - Long Path Truncation: Displaying long file paths or URLs in disabled label views can cause content truncation
       - Pattern: Add `multiline` parameter to custom view creation functions
       - Dynamic Height Calculation: When multiline is enabled, calculate view height based on text content size
       - Implementation: `string.boundingRect(with: size, options: .usesLineFragmentOrigin, attributes: context)`
       - Example: 'Token From:' display showing full auth file path instead of truncated version
         <!-- opencode:reflection:end -->
