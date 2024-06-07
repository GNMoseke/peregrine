@testable import Peregrine
import XCTest

class PeregrineTests: XCTestCase {
    func testParseList() async throws {
        let testOptions = TestOptions(
            toolchainPath: nil,
            packagePath: "TestPackage/",
            plaintextOutput: false,
            quietOutput: true,
            timingOptions: TestOptions.TestTimingOptions(
                showTimes: false,
                count: nil,
                outputFormat: .stdout,
                outputPath: ""
            )
        )

        let runner = PeregrineRunner(options: testOptions)
        let listedTests = try Set(await runner.listTests())
        let expected = Set([
            Test(suite: "SuiteOne", name: "testSuccess"),
            Test(suite: "SuiteOne", name: "testSingleFail"),
            Test(suite: "SuiteOne", name: "testThreeFail"),
            Test(suite: "SuiteOne", name: "testCustomFailMessage"),
            Test(suite: "SuiteTwo", name: "testSuccess"),
            Test(suite: "SuiteTwo", name: "testSingleFail"),
            Test(suite: "SuiteTwo", name: "testThreeFail"),
            Test(suite: "SuiteThatCrashes", name: "testFatalErrors"),
        ])
        XCTAssertEqual(listedTests, expected)
    }
}
