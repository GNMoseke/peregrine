
/// This relies heavily on the output format from swift test remaining the same, I'd like to parse xunit here
/// but spm's xunit output doesn't give valuable information: https://github.com/apple/swift-package-manager/issues/7622
func processOutput(testOutput: TestRunOutput, symbolOutput: SymbolOutput) throws -> (output: String, color: TextColor) {
    if testOutput.success {
        return (symbolOutput.getSymbol(.Success) + " All Tests Passed!", .GreenBold)
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
            \(processErrors(results: testOutput.tests, symbolOutput: symbolOutput))
            """,
            .RedBold
        )
    }
}

func processErrors(results: [TestResult], symbolOutput: SymbolOutput) throws -> String {
    var testsBySuite: [String: String] = [:]
    results.filter { !$0.passed }.forEach { result in
        let testHeader = " \(symbolOutput.getSymbol(.RightArrow)) \(symbolOutput.getSymbol(.FailedTestFlask)) \(result.test.name) - (\(result.duration))\n"
        let errors = result.errors.map { "   \(symbolOutput.getSymbol(.RightArrow)) \($0.1) \($0.0)" }.joined(separator: "\n")
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
