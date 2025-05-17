// PeregrineTests.swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing

@testable import peregrine

@Suite
struct PeregrineTests {
    var runner: PeregrineRunner!
    let testPackagePath = "TestPackage/"

    init() throws {
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

        runner = try PeregrineRunner(
            options: testOptions, logger: configureLogging("", testing: true))
    }

    @Test
    func parseList() async throws {
        let listedTests = try Set(await runner.listTests())
        let expected = Set([
            Test(suite: "SuiteOne", name: "testSuccess"),
            Test(suite: "SuiteOne", name: "testSingleFail"),
            Test(suite: "SuiteOne", name: "testThreeFail"),
            Test(suite: "SuiteOne", name: "testCustomFailMessage"),
            Test(suite: "SuiteOne", name: "testSkippedNoReason"),
            Test(suite: "SuiteOne", name: "testSkippedWithReason"),
            Test(suite: "SuiteTwo", name: "testSuccess"),
            Test(suite: "SuiteTwo", name: "testSingleFail"),
            Test(suite: "SuiteTwo", name: "testThreeFail"),
            Test(suite: "SuiteThatCrashes", name: "testFatalErrors"),
        ])
        #expect(listedTests == expected)
    }

    @Test
    func runSuccess() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: [
                "--filter", "SuiteOne/testSuccess", "--filter", "SuiteTwo/testSuccess",
            ]
        )
        let output = try await runner.runTests(testCount: 0)
        #expect(output.success)
        #expect(output.backtraceLines == nil)
        #expect(output.results.map { $0.errors }.reduce([], +).isEmpty)
    }

    @Test
    func runSingleFail() async throws {
        // Test normal single failed XCT*
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteOne/testSingleFail"]
        )
        var output = try await runner.runTests(testCount: 0)
        #expect(!output.success)
        #expect(output.backtraceLines == nil)
        var expectedErrors = [
            #"XCTAssertEqual failed: ("Arthur Morgan") is not equal to ("Dutch Van Der Linde")"#
        ]
        #expect(output.results.map { $0.errors }.reduce([], +).map { $0.1 } == expectedErrors)
        #expect(output.results.map { $0.test } == [Test(suite: "SuiteOne", name: "testSingleFail")])

        // Test single failed XCT* with a custom error message
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteOne/testCustomFailMessage"]
        )
        runner.testResults.removeAll()
        output = try await runner.runTests(testCount: 0)
        #expect(!output.success)
        #expect(output.backtraceLines == nil)
        expectedErrors =
            [
                #"XCTAssertEqual failed: ("Hosea Matthews") is not equal to ("Dutch Van Der Linde") - Always listen to Hosea"#
            ]
        #expect(output.results.map { $0.errors }.reduce([], +).map { $0.1 } == expectedErrors)
        #expect(
            output.results.map { $0.test } == [
                Test(suite: "SuiteOne", name: "testCustomFailMessage")
            ])
    }

    @Test
    func runMultipleFails() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteTwo"]
        )
        let output = try await runner.runTests(testCount: 0)
        #expect(!output.success)
        #expect(output.backtraceLines == nil)
        let expectedErrors = Set([
            #"XCTAssertEqual failed: ("Calvin") is not equal to ("Hobbes")"#,
            #"XCTAssertTrue failed"#,
            #"XCTAssertEqual failed: ("1") is not equal to ("2")"#,
            #"XCTAssertNil failed: "Zagreus""#,
        ])
        #expect(
            Set(output.results.map { $0.errors }.reduce([], +).map { $0.1 }) == expectedErrors)
        #expect(
            Set(output.results.map { $0.test })
                == Set([
                    Test(suite: "SuiteTwo", name: "testSuccess"),
                    Test(suite: "SuiteTwo", name: "testSingleFail"),
                    Test(suite: "SuiteTwo", name: "testThreeFail"),
                ])
        )
    }

    @Test
    func runFailAcrossSuites() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: [
                "--filter",
                "SuiteOne",
                "--filter",
                "SuiteTwo",
                "--skip",
                "testSkippedNoReason",
                "--skip",
                "testSkippedWithReason",
            ]
        )
        let output = try await runner.runTests(testCount: 0)
        #expect(!output.success)
        #expect(output.backtraceLines == nil)
        let expectedErrors = Set([
            #"XCTAssertEqual failed: ("Arthur Morgan") is not equal to ("Dutch Van Der Linde")"#,
            #"XCTAssertEqual failed: ("Hosea Matthews") is not equal to ("Dutch Van Der Linde") - Always listen to Hosea"#,
            #"XCTAssertEqual failed: ("Calvin") is not equal to ("Hobbes")"#,
            #"XCTAssertTrue failed"#,
            #"XCTAssertEqual failed: ("1") is not equal to ("2")"#,
            #"XCTAssertNil failed: "Zagreus""#,
        ])
        #expect(Set(output.results.map { $0.errors }.reduce([], +).map { $0.1 }) == expectedErrors)
        #expect(
            Set(output.results.map { $0.test })
                == Set([
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

    @Test
    func runFatalError() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: ["--filter", "SuiteThatCrashes"]
        )
        let output = try await runner.runTests(testCount: 0)
        #expect(!output.success)
        #expect(output.backtraceLines != nil)
    }

    @Test
    func skippedOutput() async throws {
        runner.options = TestOptions(
            toolchainPath: nil,
            packagePath: testPackagePath,
            plaintextOutput: false,
            quietOutput: true,
            additionalSwiftFlags: [
                "--filter",
                "SuiteOne/testSuccess",
                "--filter",
                "SuiteOne/testSkippedNoReason",
                "--filter",
                "SuiteOne/testSkippedWithReason",
            ]
        )
        let output = try await runner.runTests(testCount: 0)
        #expect(output.success)
        let expectedErrors = Set([
            "",
            "Lernie is hard",
        ])
        #expect(Set(output.results.map { $0.errors }.reduce([], +).map { $0.1 }) == expectedErrors)
        #expect(
            Set(output.results.filter { $0.skipped }.map { $0.test })
                == Set([
                    Test(suite: "SuiteOne", name: "testSkippedNoReason"),
                    Test(suite: "SuiteOne", name: "testSkippedWithReason"),
                ])
        )
    }
}
