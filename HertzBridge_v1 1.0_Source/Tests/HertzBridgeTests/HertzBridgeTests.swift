import XCTest
@testable import HertzBridgeCore

final class HertzBridgeTests: XCTestCase {
    func testDeviceManagerShared() {
        XCTAssertNotNil(DeviceManager.shared)
    }
}
