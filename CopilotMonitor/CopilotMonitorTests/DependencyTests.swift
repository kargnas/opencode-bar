import XCTest
@testable import CopilotMonitor

final class DependencyTests: XCTestCase {
    
    func testMenuResultBuilderExists() {
        let menu = NSMenu {
            MenuItem("Test")
        }
        XCTAssertEqual(menu.items.count, 1)
    }
    
    func testMenuDesignTokenExists() {
        XCTAssertEqual(MenuDesignToken.Dimension.menuWidth, 300)
    }
}
