//
//  MenuResultBuilder.swift
//  CopilotMonitor
//
//  Created by Result Builder Pattern
//  Purpose: Declarative NSMenu construction using Swift DSL syntax
//

import AppKit

/// Result builder for declarative NSMenu construction
/// Enables Swift DSL syntax for building menu hierarchies
@resultBuilder
struct MenuItemBuilder {
    
    /// Build a block of menu items from variadic components
    /// Used when multiple items are listed sequentially
    static func buildBlock(_ components: NSMenuItem...) -> [NSMenuItem] {
        Array(components)
    }
    
    /// Build a block from array components (for nested builders)
    /// Flattens nested arrays into a single array
    static func buildBlock(_ components: [NSMenuItem]...) -> [NSMenuItem] {
        components.flatMap { $0 }
    }
    
    /// Build optional menu items (for if statements without else)
    /// Returns empty array when condition is false
    static func buildOptional(_ component: [NSMenuItem]?) -> [NSMenuItem] {
        component ?? []
    }
    
    /// Build first branch of if-else statement
    /// Used when if condition is true
    static func buildEither(first component: [NSMenuItem]) -> [NSMenuItem] {
        component
    }
    
    /// Build second branch of if-else statement
    /// Used when if condition is false (else branch)
    static func buildEither(second component: [NSMenuItem]) -> [NSMenuItem] {
        component
    }
    
    /// Build array of menu items from for-in loops
    /// Flattens loop iterations into single array
    static func buildArray(_ components: [[NSMenuItem]]) -> [NSMenuItem] {
        components.flatMap { $0 }
    }
    
    /// Build expression from single menu item
    /// Wraps individual items into array for builder
    static func buildExpression(_ expression: NSMenuItem) -> [NSMenuItem] {
        [expression]
    }
}

extension NSMenu {
    
    /// Create NSMenu with declarative builder syntax
    /// - Parameters:
    ///   - title: Menu title (default: empty string)
    ///   - items: Builder closure that returns menu items
    /// - Example:
    ///   ```swift
    ///   let menu = NSMenu {
    ///       MenuItem("Open")
    ///       SeparatorItem()
    ///       MenuItem("Quit", keyEquivalent: "q")
    ///   }
    ///   ```
    convenience init(title: String = "", @MenuItemBuilder _ items: () -> [NSMenuItem]) {
        self.init(title: title)
        items().forEach { addItem($0) }
    }
    
    /// Replace all menu items with new items using builder syntax
    /// - Parameter items: Builder closure that returns new menu items
    /// - Example:
    ///   ```swift
    ///   menu.replaceItems {
    ///       MenuItem("New Item 1")
    ///       MenuItem("New Item 2")
    ///   }
    ///   ```
    func replaceItems(@MenuItemBuilder with items: () -> [NSMenuItem]) {
        removeAllItems()
        items().forEach { addItem($0) }
    }
}

// MARK: - Helper Functions

/// Create a separator menu item
/// - Returns: NSMenuItem configured as separator
/// - Example:
///   ```swift
///   let menu = NSMenu {
///       MenuItem("Before")
///       SeparatorItem()
///       MenuItem("After")
///   }
///   ```
func SeparatorItem() -> NSMenuItem {
    NSMenuItem.separator()
}

/// Create a menu item with title, action, and key equivalent
/// - Parameters:
///   - title: Display text for the menu item
///   - action: Selector to call when item is clicked (default: nil)
///   - keyEquivalent: Keyboard shortcut (default: empty string)
/// - Returns: Configured NSMenuItem
/// - Example:
///   ```swift
///   MenuItem("Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
///   ```
func MenuItem(
    _ title: String,
    action: Selector? = nil,
    keyEquivalent: String = ""
) -> NSMenuItem {
    NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
}
