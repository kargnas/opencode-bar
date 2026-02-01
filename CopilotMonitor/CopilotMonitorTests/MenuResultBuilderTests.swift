//
//  MenuResultBuilderTests.swift
//  CopilotMonitorTests
//
//  Created by Result Builder TDD
//

import XCTest
@testable import CopilotMonitor

final class MenuResultBuilderTests: XCTestCase {
    
    func testBuildBlockWithItems() {
        let menu = NSMenu {
            MenuItem("Item 1")
            MenuItem("Item 2")
            MenuItem("Item 3")
        }
        XCTAssertEqual(menu.items.count, 3)
        XCTAssertEqual(menu.items[0].title, "Item 1")
        XCTAssertEqual(menu.items[1].title, "Item 2")
        XCTAssertEqual(menu.items[2].title, "Item 3")
    }
    
    func testBuildBlockWithSeparator() {
        let menu = NSMenu {
            MenuItem("Before")
            SeparatorItem()
            MenuItem("After")
        }
        XCTAssertEqual(menu.items.count, 3)
        XCTAssertEqual(menu.items[0].title, "Before")
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, "After")
    }
    
    func testBuildOptionalNil() {
        let showItem: Bool = false
        let menu = NSMenu {
            MenuItem("Always")
            if showItem {
                MenuItem("Sometimes")
            }
        }
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items[0].title, "Always")
    }
    
    func testBuildOptionalPresent() {
        let showItem: Bool = true
        let menu = NSMenu {
            MenuItem("Always")
            if showItem {
                MenuItem("Sometimes")
            }
        }
        XCTAssertEqual(menu.items.count, 2)
        XCTAssertEqual(menu.items[0].title, "Always")
        XCTAssertEqual(menu.items[1].title, "Sometimes")
    }
    
    func testBuildEither() {
        let useAlternate: Bool = true
        let menu = NSMenu {
            if useAlternate {
                MenuItem("Alternate")
            } else {
                MenuItem("Default")
            }
        }
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items[0].title, "Alternate")
    }
    
    func testBuildEitherElse() {
        let useAlternate: Bool = false
        let menu = NSMenu {
            if useAlternate {
                MenuItem("Alternate")
            } else {
                MenuItem("Default")
            }
        }
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items[0].title, "Default")
    }
    
    func testBuildArray() {
        let items = ["A", "B", "C"]
        let menu = NSMenu {
            for item in items {
                MenuItem(item)
            }
        }
        XCTAssertEqual(menu.items.count, 3)
        XCTAssertEqual(menu.items.map { $0.title }, ["A", "B", "C"])
    }
    
    func testBuildArrayEmpty() {
        let items: [String] = []
        let menu = NSMenu {
            for item in items {
                MenuItem(item)
            }
        }
        XCTAssertEqual(menu.items.count, 0)
    }
    
    func testMenuItemWithKeyEquivalent() {
        let item = MenuItem("Quit", keyEquivalent: "q")
        XCTAssertEqual(item.title, "Quit")
        XCTAssertEqual(item.keyEquivalent, "q")
    }
    
    func testMenuItemWithAction() {
        let item = MenuItem("Test", action: #selector(NSApplication.terminate(_:)))
        XCTAssertEqual(item.title, "Test")
        XCTAssertEqual(item.action, #selector(NSApplication.terminate(_:)))
    }
    
    func testReplaceItems() {
        let menu = NSMenu {
            MenuItem("Original")
        }
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items[0].title, "Original")
        
        menu.replaceItems {
            MenuItem("New 1")
            MenuItem("New 2")
        }
        XCTAssertEqual(menu.items.count, 2)
        XCTAssertEqual(menu.items[0].title, "New 1")
        XCTAssertEqual(menu.items[1].title, "New 2")
    }
    
    func testComplexNestedStructure() {
        let hasSubmenu = true
        let items = ["Sub 1", "Sub 2"]
        
        let menu = NSMenu {
            MenuItem("First")
            SeparatorItem()
            
            if hasSubmenu {
                MenuItem("With Submenu")
                for item in items {
                    MenuItem(item)
                }
            }
            
            SeparatorItem()
            MenuItem("Last", keyEquivalent: "l")
        }
        
        XCTAssertEqual(menu.items.count, 7)
        XCTAssertEqual(menu.items[0].title, "First")
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, "With Submenu")
        XCTAssertEqual(menu.items[3].title, "Sub 1")
        XCTAssertEqual(menu.items[4].title, "Sub 2")
        XCTAssertTrue(menu.items[5].isSeparatorItem)
        XCTAssertEqual(menu.items[6].title, "Last")
        XCTAssertEqual(menu.items[6].keyEquivalent, "l")
    }
    
    func testMenuWithTitle() {
        let menu = NSMenu(title: "Test Menu") {
            MenuItem("Item")
        }
        XCTAssertEqual(menu.title, "Test Menu")
        XCTAssertEqual(menu.items.count, 1)
    }
}
