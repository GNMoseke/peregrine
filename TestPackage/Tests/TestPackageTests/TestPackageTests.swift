// TestPackageTests.swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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

    func testSkippedNoReason() throws {
        throw XCTSkip()
    }

    func testSkippedWithReason() throws {
        throw XCTSkip("Lernie is hard")
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
}

final class SuiteThatCrashes: XCTestCase {
    func testFatalErrors() {
        let nilItem: String? = nil
        _ = nilItem!.max()
    }
}
