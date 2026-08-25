import XCTest

@testable import Kanamon

final class KanamonTests: XCTestCase {
  func testContentViewCanBeInstantiated() {
    XCTAssertNotNil(ContentView().body)
  }
}
