/// This relies heavily on the output format from swift test remaining the same, I'd like to parse xunit here
/// but spm's xunit output doesn't give valuable information: https://github.com/apple/swift-package-manager/issues/7622
func processOutput(testOutput: TestRunOutput, symbolOutput: SymbolOutput) throws -> (output: String, color: TextColor) {
    let skippedTests = testOutput.results.filter { $0.skipped }
        .map { $0.test.fullName + $0.errors.map { ": \($0.1)" }.joined(separator: " ") }
    if testOutput.success {
        return (
            """


            \(symbolOutput.getSymbol(.success)) All Tests Passed!
            \(skippedTests.count > 0 ? """
            The following tests were skipped:
            \(skippedTests.joined(separator: "\n"))
            """ : "")
            """,
            .greenBold
        )
    } else if let backtraceLines = testOutput.backtraceLines {
        return (
            """


            === TESTS CRASHED ===
            \(backtraceLines.joined(separator: "\n"))
            """,
            .redBold
        )
    } else {
        return try (
            """


            === TESTS FAILED ===
            \(processErrors(results: testOutput.results, symbolOutput: symbolOutput))
            \(skippedTests.count > 0 ? """
            The following tests were skipped:
            \(skippedTests.joined(separator: "\n"))
            """ : "")
            """,
            .redBold
        )
    }
}

func processErrors(results: [TestResult], symbolOutput: SymbolOutput) throws -> String {
    var testsBySuite: [String: String] = [:]
    for result in results.filter({ !$0.passed }) {
        let testHeader =
            " \(symbolOutput.getSymbol(.rightArrow)) \(symbolOutput.getSymbol(.failedTestFlask)) \(result.test.name) - (\(result.duration))\n"
        let errors = result.errors.map { "   \(symbolOutput.getSymbol(.rightArrow)) \($0.1) -> \($0.0)" }
            .joined(separator: "\n")
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
