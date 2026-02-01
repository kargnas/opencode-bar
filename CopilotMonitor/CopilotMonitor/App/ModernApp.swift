import SwiftUI
import MenuBarExtraAccess

/// Modern SwiftUI entry point for the app
/// Uses MenuBarExtra with NSMenu bridge for full native menu support
@main
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
