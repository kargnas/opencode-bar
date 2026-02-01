import SwiftUI
import MenuBarExtraAccess

/// Modern SwiftUI entry point for the app
/// NOTE: @main attribute will be added later when we switch from CopilotMonitorApp
struct ModernApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isMenuPresented = false
    
    var body: some Scene {
        MenuBarExtra {
            Text("Loading...") // Placeholder, will be replaced by NSMenu bridge
        } label: {
            Image(systemName: "gauge.medium")
        }
        .menuBarExtraStyle(.menu)
        .menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
            if let controller = appDelegate.statusBarController {
                controller.attachTo(statusItem)
            }
        }
        
        Settings {
            EmptyView()
        }
    }
}
