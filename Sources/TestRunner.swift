import Foundation
import SwiftCommand

struct TestRunOutput {
    let success: Bool
    let tests: [TestResult]
    let backtraceLines: [String]?
}

struct TestOptions {
    let parallel: Bool
    // implies parallel
    let generateXunit: Bool
    let toolchainPath: String
    let packagePath: String
}

struct Test: Codable, Hashable {
    let suite: String
    let name: String

    var fullName: String {
        "\(suite).\(name)"
    }
}

struct TestResult {
    let test: Test
    let passed: Bool
    // line, failure message
    var errors: [(String, String)]
    var duration: Duration
}

protocol TestRunner {
    var options: TestOptions { get }
    func listTests() async throws -> [Test]
    func runTests(tests: [Test]) async throws -> TestRunOutput
    func output(results: TestRunOutput) throws
}

class PeregrineRunner: TestRunner {
    let options: TestOptions
    var testResults: [Test: TestResult] = [:]

    init(options: TestOptions) {
        self.options = options
    }

    func listTests() async throws -> [Test] {
        print(NerdFontIcons.Build.rawValue + " Building...", .CyanBold)
        let listProcess = try Command(executablePath: .init(options.toolchainPath))
            .addArguments(["test", "list", "--package-path", options.packagePath])
            .setStdout(.pipe)
            .setStderr(.pipe)
            .spawn()

        var tests = [Test]()
        for try await line in listProcess.stdout.lines {
            var split = line.split(separator: ".")
            guard let testTarget = split.first, let remainder = split.last else {
                // FIXME: convert to thrown error
                print("Boom")
                return []
            }
            split = remainder.split(separator: "/")
            guard let testClass = split.first, let testName = split.last else {
                // FIXME: convert to thrown error
                print("boom 2")
                return []
            }
            tests.append(Test(suite: String(testClass), name: String(testName)))
        }
        return tests
    }

    func runTests(tests: [Test]) async throws -> TestRunOutput {
        let testCount = tests.count
        let testProcess = try Command(executablePath: .init(options.toolchainPath))
            .addArguments(["test", "--package-path", options.packagePath] + (options.parallel ? ["--parallel"] : []))
            .setStdout(.pipe) // swift build diagnostics go to stder
            .setStderr(.pipe)
            .spawn()

        print(NerdFontIcons.ErlenmeyerFlask.rawValue + " Running Tests...", .CyanBold)

        let progressBarCharacterLength = 45
        let stepSize: Int = testCount / progressBarCharacterLength
        var completeTests = 0
        var progressIndex = 0
        var progressBar = String(repeating: NerdFontIcons.LightlyShadedBlock.rawValue, count: progressBarCharacterLength)
        print(progressBar, terminator: "\r")
        fflush(nil)
        var backtraceLines = [String]()
        var collectBacktrace = false
        // TODO: clean this up, very heavy-handed processing
        for try await line in testProcess.stdout.lines {
            if collectBacktrace {
                backtraceLines.append(line)
                continue
            } else if line.contains("Fatal error:") {
                backtraceLines.append(line)
                collectBacktrace = true
            }
            if try parseTestLine(line) {
                completeTests += 1
                if completeTests % stepSize == 0 {
                    progressBar = String(progressBar.dropLast())
                    progressBar.insert(Character(NerdFontIcons.FilledBlock.rawValue), at: progressBar.startIndex)
                    progressIndex += 1
                    print(progressBar, terminator: "\r")
                    fflush(nil)
                }
            }
        }
        print("\n")
        try testProcess.wait()
        if try await testProcess.status.terminatedSuccessfully {
            return TestRunOutput(success: true, tests: Array(testResults.values), backtraceLines: nil)
        } else {
            return TestRunOutput(success: false, tests: Array(testResults.values), backtraceLines: backtraceLines.isEmpty ? nil : backtraceLines)
        }
    }

    func output(results: TestRunOutput) throws {
        let processedOutput = try processOutput(testOutput: results)
        print(processedOutput.output, processedOutput.color)
    }

    private func parseTestLine(_ line: String) throws -> Bool {
        // FIXME: pretty brute-force here, should use a regex
        if line.starts(with: "Test Case") && !line.contains("started at") {
            var processedLine = line
            processedLine.removeFirst("Test Case '".count)
            let components = processedLine.split(separator: "'")
            guard let fullTestName = components.first else {
                throw TestOutputParseError.unexpectedLineFormat("could not parse completion line: \(line)")
            }
            // TODO: I do this split a lot, should just write a processing function for it
            let nameComponents = fullTestName.split(separator: ".")
            guard let testSuite = nameComponents.first, let testName = nameComponents.last else {
                throw TestOutputParseError.unexpectedLineFormat("could not parse test name from line: \(line)")
            }
            let test = Test(suite: String(testSuite), name: String(testName))

            guard let timeString = processedLine.split(separator: "(").last?.split(separator: " ").first, let testDuration = Double(String(timeString)) else {
                throw TestOutputParseError.unexpectedLineFormat("Could not parse time from line: \(line)")
            }

            if line.contains("passed") {
                testResults[test] = TestResult(test: test, passed: true, errors: [], duration: .seconds(testDuration))
                return true
            }
            if line.contains("failed") {
                testResults[test]?.duration = .seconds(testDuration)
                return true
            }
        } else if line.contains("error:") {
            let errorComponents = line.split(separator: "error:")
            guard let errorLocation = errorComponents.first, let testAndFail = errorComponents.last else {
                throw TestOutputParseError.unexpectedLineFormat("Could not parse error line: \(line)")
            }
            let location = String(errorLocation.trimmingCharacters(in: [":", " "]))
            let failureComponents = testAndFail.split(separator: ":")
            guard let testName = failureComponents.first?.trimmingCharacters(in: .whitespaces), let failure = failureComponents.last else {
                throw TestOutputParseError.unexpectedLineFormat("Could not parse error line, failed to pull test failure: \(line)")
            }
            let testNameComponents = testName.split(separator: ".")
            let test = Test(suite: String(testNameComponents.first!), name: String(testNameComponents.last!))
            testResults[test, default: TestResult(test: test, passed: false, errors: [], duration: .seconds(0))].errors.append((location, String(failure)))
            return false
        }
        return false
    }
}

enum TestOutputParseError: Error {
    case unexpectedLineFormat(String)
}
