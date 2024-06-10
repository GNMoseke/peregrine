@testable import peregrine
import XCTest

class PeregrineTests: XCTestCase {
    var runner: PeregrineRunner!
    let testPackagePath = "TestPackage/"

    override func setUp() {
        let testOptions = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            timingOptions: TestOptions.TestTimingOptions(
                showTimes: false,
                count: nil,
                outputFormat: .stdout,
                outputPath: ""
            )
        )

        runner = PeregrineRunner(options: testOptions)
    }

    func testParseList() async throws {
        try XCTSkipIf(true, "fdjfldskfjslk")
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

    func testRunSuccess() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteOne/testSuccess", "--filter", "SuiteTwo/testSuccess"]
        )
        let output = try await runner.runTests(tests: [])
        XCTAssertTrue(output.success)
        XCTAssertNil(output.backtraceLines)
        XCTAssertTrue(output.results.map { $0.errors }.reduce([], +).isEmpty)
    }

    func testRunSingleFail() async throws {
        // Test normal single failed XCT*
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteOne/testSingleFail"]
        )
        var output = try await runner.runTests(tests: [])
        XCTAssertFalse(output.success)
        XCTAssertNil(output.backtraceLines)
        var expectedErrors = [#"("Arthur Morgan") is not equal to ("Dutch Van Der Linde")"#]
        XCTAssertEqual(output.results.map { $0.errors }.reduce([], +).map { $0.1 }, expectedErrors)
        XCTAssertEqual(output.results.map { $0.test }, [Test(suite: "SuiteOne", name: "testSingleFail")])

        // Test single failed XCT* with a custom error message
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteOne/testCustomFailMessage"]
        )
        runner.testResults.removeAll()
        output = try await runner.runTests(tests: [])
        XCTAssertFalse(output.success)
        XCTAssertNil(output.backtraceLines)
        expectedErrors = [#"("Hosea Matthews") is not equal to ("Dutch Van Der Linde") - Always listen to Hosea"#]
        XCTAssertEqual(output.results.map { $0.errors }.reduce([], +).map { $0.1 }, expectedErrors)
        XCTAssertEqual(output.results.map { $0.test }, [Test(suite: "SuiteOne", name: "testCustomFailMessage")])
    }

    func testRunMultipleFails() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteTwo"]
        )
        let output = try await runner.runTests(tests: [])
        XCTAssertFalse(output.success)
        XCTAssertNil(output.backtraceLines)
        let expectedErrors = Set([
            #"("Calvin") is not equal to ("Hobbes")"#,
            #"XCTAssertTrue failed"#,
            #"("1") is not equal to ("2")"#,
            #""Zagreus""#,
        ])
        XCTAssertEqual(Set(output.results.map { $0.errors }.reduce([], +).map { $0.1 }), expectedErrors)
        XCTAssertEqual(
            Set(output.results.map { $0.test }),
            Set([
                Test(suite: "SuiteTwo", name: "testSuccess"),
                Test(suite: "SuiteTwo", name: "testSingleFail"),
                Test(suite: "SuiteTwo", name: "testThreeFail"),
            ])
        )
    }

    func testRunFailAcrossSuites() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteOne", "--filter", "SuiteTwo"]
        )
        let output = try await runner.runTests(tests: [])
        XCTAssertFalse(output.success)
        XCTAssertNil(output.backtraceLines)
        let expectedErrors = Set([
            #"("Arthur Morgan") is not equal to ("Dutch Van Der Linde")"#,
            #"("Hosea Matthews") is not equal to ("Dutch Van Der Linde") - Always listen to Hosea"#,
            #"("Calvin") is not equal to ("Hobbes")"#,
            #"XCTAssertTrue failed"#,
            #"("1") is not equal to ("2")"#,
            #""Zagreus""#,
        ])
        XCTAssertEqual(Set(output.results.map { $0.errors }.reduce([], +).map { $0.1 }), expectedErrors)
        XCTAssertEqual(
            Set(output.results.map { $0.test }),
            Set([
                Test(suite: "SuiteOne", name: "testSuccess"),
                Test(suite: "SuiteOne", name: "testSingleFail"),
                Test(suite: "SuiteOne", name: "testThreeFail"),
                Test(suite: "SuiteOne", name: "testCustomFailMessage"),
                Test(suite: "SuiteTwo", name: "testSuccess"),
                Test(suite: "SuiteTwo", name: "testSingleFail"),
                Test(suite: "SuiteTwo", name: "testThreeFail"),
            ])
        )
    }

    func testRunFatalError() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteThatCrashes"]
        )
        let output = try await runner.runTests(tests: [])
        XCTAssertFalse(output.success)
        XCTAssertNotNil(output.backtraceLines)
    }
}
