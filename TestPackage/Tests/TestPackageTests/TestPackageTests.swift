import XCTest

final class SuiteOne: XCTestCase {
    func testSuccess() {
        XCTAssertTrue(true)
    }

    func testSingleFail() {
        XCTAssertEqual("Arthur Morgan", "Dutch Van Der Linde")
    }

    func testThreeFail() {
        XCTAssertTrue(false)
        XCTAssertEqual(1, 2)
        XCTAssertNil("Zagreus")
    }

    func testCustomFailMessage() {
       XCTAssertEqual("Hosea Matthews", "Dutch Van Der Linde", "Always listen to Hosea") 
    }
}

final class SuiteTwo: XCTestCase {
    func testSuccess() {
        XCTAssertTrue(true)
    }

    func testSingleFail() {
        XCTAssertEqual("Calvin", "Hobbes")
    }

    func testThreeFail() {
        XCTAssertTrue(false)
        XCTAssertEqual(1, 2)
        XCTAssertNil("Zagreus")
    }

    // func testLong() {
    //     sleep(1)
    // }

    // func testLonger() {
    //     sleep(2)
    // }

    // func testLongest() {
    //     sleep(3)
    // }
}

final class SuiteThatCrashes: XCTestCase {
    func testFatalErrors() {
        let nilItem: String? = nil
        _ = nilItem!.max()
    }
}
