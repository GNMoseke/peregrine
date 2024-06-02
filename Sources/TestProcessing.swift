
/// This relies heavily on the output format from swift test remaining the same, I'd like to parse xunit here
/// but spm's xunit output doesn't give valuable information: https://github.com/apple/swift-package-manager/issues/7622
func processOutput(testOutput: TestRunOutput) throws -> (output: String, color: TextColor) {
    if testOutput.success {
        return (NerdFontIcons.Success.rawValue + " All Tests Passed!", .GreenBold)
    } else if let backtraceLines = testOutput.backtraceLines {
        return (
            """
            === TESTS CRASHED ===
            \(backtraceLines.joined(separator: "\n"))
            """,
            .RedBold
        )
    } else {
        return try (
            """
            === TESTS FAILED ===
            \(processErrors(results: testOutput.tests))
            """,
            .RedBold
        )
    }
}

func processErrors(results: [TestResult]) throws -> String {
    var testsBySuite: [String: String] = [:]
    results.filter { !$0.passed }.forEach { result in
        let testHeader = " \(NerdFontIcons.RightArrow.rawValue) \(NerdFontIcons.FailedTestFlask.rawValue) \(result.test.name) - (\(result.duration))\n"
        let errors = result.errors.map { "   \(NerdFontIcons.RightArrow.rawValue) \($0.1) \($0.0)" }.joined(separator: "\n")
        testsBySuite[result.test.suite, default: ""] += testHeader + errors + "\n"
    }
    var finalOutput = ""
    for (suite, testInfo) in testsBySuite {
        finalOutput += suite + "\n" + testInfo + "\n"
    }
    return finalOutput
}

enum TestProcessingError: Error {
    case failedWithoutOutput(String)
}
