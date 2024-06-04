import Foundation
import SwiftCommand

struct TestRunOutput {
    let success: Bool
    let tests: [TestResult]
    let backtraceLines: [String]?
}

struct TestOptions {
    struct TestTimingOptions {
        let showTimes: Bool
        let count: Int?
        let outputFormat: LongTestOutputFormat
        let outputPath: String
    }

    let toolchainPath: String
    let packagePath: String
    let timingOptions: TestTimingOptions

    init(toolchainPath: String, packagePath: String, timingOptions: TestTimingOptions = TestTimingOptions(showTimes: false, count: nil, outputFormat: .stdout, outputPath: "/dev/null")) {
        self.toolchainPath = toolchainPath
        self.packagePath = packagePath
        self.timingOptions = timingOptions
    }
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
            guard let remainder = line.split(separator: ".").last else {
                throw TestParseError.unexpectedLineFormat("Could not parse test definition from \(line)")
            }
            let suiteAndName = remainder.split(separator: "/")
            guard let testSuite = suiteAndName.first, let testName = suiteAndName.last else {
                throw TestParseError.unexpectedLineFormat("Could not parse test definition from \(line)")
            }
            tests.append(Test(suite: String(testSuite), name: String(testName)))
        }
        return tests
    }

    func runTests(tests: [Test]) async throws -> TestRunOutput {
        let testCount = tests.count
        let testProcess = try Command(executablePath: .init(options.toolchainPath))
            .addArguments(["test", "--package-path", options.packagePath])
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

        if options.timingOptions.showTimes {
            var sortedByTime = results.tests.sorted(by: { $0.duration > $1.duration })
            if let countLimit = options.timingOptions.count {
                sortedByTime = Array(sortedByTime[0 ..< countLimit])
            }
            switch options.timingOptions.outputFormat {
            case .stdout:
                print("=== \(NerdFontIcons.Timer.rawValue) SLOWEST TESTS ===", .CyanBold)
                for (idx, result) in sortedByTime.enumerated() {
                    // TODO: line up the lines, just generally clean up this output
                    print("\(idx + 1) | \(result.test.fullName) (\(result.passed ? "Succeeded" : "Failed")): \(result.duration)", result.passed ? .GreenBold : .RedBold)
                }
            case .csv:
                let lines = "Suite,Name,Time (s),Passed\n" + sortedByTime.map { "\($0.test.suite),\($0.test.name),\($0.duration),\($0.passed)" }.joined(separator: "\n")
                FileManager.default.createFile(atPath: options.timingOptions.outputPath, contents: lines.data(using: .ascii))
                print("Successfully output test times to \(options.timingOptions.outputPath)", .Cyan)
            }
        }
    }

    private func parseTestLine(_ line: String) throws -> Bool {
        // FIXME: pretty brute-force here, should use a regex
        if line.starts(with: "Test Case") && !line.contains("started at") {
            var processedLine = line
            processedLine.removeFirst("Test Case '".count)
            let components = processedLine.split(separator: "'")
            guard let fullTestName = components.first else {
                throw TestParseError.unexpectedLineFormat("could not parse completion line: \(line)")
            }
            // TODO: I do this split a lot, should just write a processing function for it
            let nameComponents = fullTestName.split(separator: ".")
            guard let testSuite = nameComponents.first, let testName = nameComponents.last else {
                throw TestParseError.unexpectedLineFormat("could not parse test name from line: \(line)")
            }
            let test = Test(suite: String(testSuite), name: String(testName))

            guard let timeString = processedLine.split(separator: "(").last?.split(separator: " ").first, let testDuration = Double(String(timeString)) else {
                throw TestParseError.unexpectedLineFormat("Could not parse time from line: \(line)")
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
                throw TestParseError.unexpectedLineFormat("Could not parse error line: \(line)")
            }
            let location = String(errorLocation.trimmingCharacters(in: [":", " "]))
            let failureComponents = testAndFail.split(separator: ":")
            guard let testName = failureComponents.first?.trimmingCharacters(in: .whitespaces), let failure = failureComponents.last else {
                throw TestParseError.unexpectedLineFormat("Could not parse error line, failed to pull test failure: \(line)")
            }
            let testNameComponents = testName.split(separator: ".")
            let test = Test(suite: String(testNameComponents.first!), name: String(testNameComponents.last!))
            testResults[test, default: TestResult(test: test, passed: false, errors: [], duration: .seconds(0))].errors.append((location, String(failure)))
            return false
        }
        return false
    }
}

enum TestParseError: Error {
    case unexpectedLineFormat(String)
}
