
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
    } else if let errorLines = testOutput.errorLines {
        return try (
            """
            === TESTS FAILED ===
            \(processErrors(tests: testOutput.tests, errorLines: errorLines))
            """,
            .RedBold
        )
    } else {
        throw TestProcessingError.failedWithoutOutput("Tests failed, and no errors/backtrace were found")
    }
}

func processErrors(tests: [Test], errorLines: [String]) throws -> String {
    var errorsByTest = [Test: [String]]()
    // FIXME: force unwraps
    for line in errorLines {
        let failure = line.split(separator: "error:").last!
        let failureComponents = failure.split(separator: ":")
        let testIdentifierComponents = failureComponents.first?.split(separator: ".")
        let testClass = testIdentifierComponents?.first?.trimmingCharacters(in: .whitespaces)
        let name = testIdentifierComponents?.last?.trimmingCharacters(in: .whitespaces)
        if let test = tests.first(where: { $0.class == testClass && $0.name == name }), let failureInfo = failureComponents.last {
            errorsByTest[test, default: []].append(String(failureInfo))
        }
    }
    // TODO: include file and line here too
    var processed = ""
    for (test, errors) in errorsByTest {
        processed += NerdFontIcons.Failure.rawValue + " \(test.fullName):\n"
        processed += errors.map { "  \(NerdFontIcons.RightArrow.rawValue) \($0)" }.joined(separator: "\n")
    }
    return processed
}

enum TestProcessingError: Error {
    case failedWithoutOutput(String)
}
