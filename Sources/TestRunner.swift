import Foundation
import Puppy
import SwiftCommand

struct TestRunOutput {
    let success: Bool
    let results: [TestResult]
    let backtraceLines: [String]?
}

struct TestOptions {
    struct TestTimingOptions {
        let showTimes: Bool
        let count: Int?
        let outputFormat: LongTestOutputFormat
        let outputPath: String
    }

    let toolchainPath: String?
    let packagePath: String
    let timingOptions: TestTimingOptions
    let symbolOutput: SymbolOutput
    let additionalSwiftFlags: [String]
    let quietOutput: Bool

    init(
        toolchainPath: String?,
        packagePath: String,
        plaintextOutput: Bool,
        quietOutput: Bool = false,
        additionalSwiftFlags: [String] = [],
        timingOptions: TestTimingOptions = TestTimingOptions(
            showTimes: false,
            count: nil,
            outputFormat: .stdout,
            outputPath: "/dev/null"
        )
    ) {
        self.toolchainPath = toolchainPath
        self.packagePath = packagePath
        self.timingOptions = timingOptions
        self.additionalSwiftFlags = additionalSwiftFlags
        symbolOutput = SymbolOutput(plaintext: plaintextOutput)
        self.quietOutput = quietOutput
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
    let skipped: Bool
    // line, failure message
    var errors: [(String, String)]
    var duration: Duration
}

protocol TestRunner {
    var options: TestOptions { get set }
    func listTests() async throws -> [Test]
    func runTests(tests: [Test]) async throws -> TestRunOutput
    func output(results: TestRunOutput) throws
}

class PeregrineRunner: TestRunner {
    var options: TestOptions
    var testResults: [Test: TestResult] = [:]

    private let logger: Puppy
    private let packagePathPrefix: String

    init(options: TestOptions, logger: Puppy) {
        self.options = options
        self.logger = logger
        packagePathPrefix = (Foundation.URL(string: options.packagePath)?.path ?? "") +
            (options.packagePath.last == "/" ? "" : "/")
    }

    func listTests() async throws -> [Test] {
        logger.info("Listing Tests at \(options.packagePath)")
        guard
            FileManager.default
                .fileExists(atPath: options.packagePath + (options.packagePath.last == "/" ? "" : "/") + "Package.swift")
        else {
            logger.error("Path given was not a swift package")
            throw TestParseError.notSwiftPackage
        }

        let buildingTask = Task(priority: .utility) {
            if !self.options.quietOutput {
                let spinnerStates = ["/", "-", #"\"#, "|"]
                var iteration = 0
                repeat {
                    self.logger.trace("Rotating spinner...")
                    print(
                        self.options.symbolOutput
                            .getSymbol(.Build) + " Building... \(spinnerStates[iteration % spinnerStates.count])",
                        terminator: "\r",
                        .CyanBold
                    )
                    fflush(nil)
                    iteration += 1
                    try? await Task.sleep(for: .milliseconds(100.0))
                } while !Task.isCancelled
            }
        }

        defer {
            buildingTask.cancel()
            logger.debug("Spinner cancelled")
        }

        guard
            let listProcess = try (
                options.toolchainPath == nil ? Command
                    .findInPath(withName: "swift") : Command(executablePath: .init(options.toolchainPath!))
            )?
                .addArguments(["test", "list", "--package-path", options.packagePath])
                .addArguments(options.additionalSwiftFlags)
                .setStdout(.pipe)
                .setStderr(.pipe)
                .spawn()
        else {
            throw PeregrineError.couldNotFindSwiftExecutable
        }

        var tests = [Test]()
        for try await line in listProcess.stdout.lines {
            logger.trace("swift test list stdout: \(line)")
            guard let remainder = line.split(separator: ".").last else {
                throw TestParseError.unexpectedLineFormat("Could not parse test definition from \(line)")
            }
            let suiteAndName = remainder.split(separator: "/")
            guard let testSuite = suiteAndName.first, let testName = suiteAndName.last else {
                throw TestParseError.unexpectedLineFormat("Could not parse test definition from \(line)")
            }
            let test = Test(suite: String(testSuite), name: String(testName))
            logger.debug("Found test: \(test)")
            tests.append(test)
        }

        var collectBuildFailure = false
        var buildFailLines: [String] = []
        for try await line in listProcess.stderr.lines {
            logger.trace("swift test list stderr: \(line)")
            if collectBuildFailure {
                buildFailLines.append(line)
            }
            if !collectBuildFailure && line.contains("error:") && line.contains(".swift") {
                logger.debug("Build failure found, collecting remaining stderr")
                collectBuildFailure = true
            }
        }

        let status = try await listProcess.status
        // NOTE: the SwiftCommand package uses `nil` to represent a successful exit code of 0, which is a little
        // confusing
        logger.info("Build/List finished with code \(status.exitCode ?? 0)")
        if !(status.terminatedSuccessfully) {
            print("=== BUILD FAILED ===", .RedBold)
            print(buildFailLines.joined(separator: "\n"), .RedBold)
            throw TestParseError.buildFailure
        }
        logger.trace("Found tests: \(tests)")
        return tests
    }

    func runTests(tests: [Test]) async throws -> TestRunOutput {
        // TODO: the tests parameter here is somewhat confusing since it only gets used for couting the number being run
        // The way to filter/skip is to pass the relevant flag via the passthrough option in peregrine, but that feels a
        // little funky
        // I'd like to refactor this to filter to the given test array in this function, but then there has to be some
        // extra
        // parsing done to see if --filter or --skip were included and respect them accordingly - `swift test list` does
        // not use those flags
        let testCount = tests.count == 0 ? 1 : tests.count
        guard
            let testProcess = try (
                options.toolchainPath == nil ? Command
                    .findInPath(withName: "swift") : Command(executablePath: .init(options.toolchainPath!))
            )?
                .addArguments(["test", "--package-path", options.packagePath])
                .addArguments(options.additionalSwiftFlags)
                .setStdout(.pipe) // swift build diagnostics go to stder
                .setStderr(.pipe)
                .spawn()
        else {
            throw PeregrineError.couldNotFindSwiftExecutable
        }

        let progressBarCharacterLength = 45
        let stepSize: Int = testCount < progressBarCharacterLength ? progressBarCharacterLength / testCount :
            testCount /
            progressBarCharacterLength
        var completeTests = 0
        var progressBar = String(
            repeating: options.symbolOutput.getSymbol(.LightlyShadedBlock),
            count: progressBarCharacterLength
        )

        if !options.quietOutput {
            print(options.symbolOutput.getSymbol(.ErlenmeyerFlask) + " Running Tests...", .CyanBold)
            print(progressBar, terminator: "\r")
            fflush(nil)
        }

        var backtraceLines = [String]()
        var collectBacktrace = false
        // TODO: clean this up, very heavy-handed processing
        for try await line in testProcess.stdout.lines {
            logger.trace("swift test stdout: \(line)")
            if collectBacktrace {
                backtraceLines.append(line)
                continue
            } else if line.contains("Fatal error:") {
                // FIXME: There are other cases for crash as well, the above is for fatalerror/try!
                backtraceLines.append(line)
                collectBacktrace = true
            }
            if try parseTestLine(line) && !options.quietOutput {
                // TODO: nicer output for test suites less than the progress bar length. This still looks a tad jank.
                completeTests += 1
                if testCount < progressBarCharacterLength {
                    // in the case that we have fewer tests than the length of the bar, fill in more than 1 block
                    for _ in 0 ..< stepSize {
                        progressBar = refreshProgressBar(progressBar)
                    }
                    print(progressBar, terminator: "\r")
                    fflush(nil)
                } else if completeTests % stepSize == 0 {
                    progressBar = refreshProgressBar(progressBar)
                    print(progressBar, terminator: "\r")
                    fflush(nil)
                }
            }
        }

        // this could maybe be misleading, but finish the bar when tests finish no matter what
        if !options.quietOutput {
            print(String(
                repeating: options.symbolOutput.getSymbol(.FilledBlock),
                count: progressBarCharacterLength
            ))
        }

        let status = try await testProcess.status
        // NOTE: the SwiftCommand package uses `nil` to represent a successful exit code of 0, which is a little
        // confusing
        logger.info("Tests finished with code \(status.exitCode ?? 0)")
        if status.terminatedSuccessfully {
            return TestRunOutput(success: true, results: Array(testResults.values), backtraceLines: nil)
        } else {
            return TestRunOutput(
                success: false,
                results: Array(testResults.values),
                backtraceLines: backtraceLines.isEmpty ? nil : backtraceLines
            )
        }
    }

    private func refreshProgressBar(_ progressBar: String) -> String {
        var newProgressBar = String(progressBar.dropLast())
        newProgressBar.insert(
            Character(options.symbolOutput.getSymbol(.FilledBlock)),
            at: progressBar.startIndex
        )
        return newProgressBar
    }

    func output(results: TestRunOutput) throws {
        let processedOutput = try processOutput(testOutput: results, symbolOutput: options.symbolOutput)
        print(processedOutput.output, processedOutput.color)

        if options.timingOptions.showTimes {
            var sortedByTime = results.results.sorted(by: { $0.duration > $1.duration })
            if let countLimit = options.timingOptions.count {
                sortedByTime = Array(sortedByTime[0 ..< countLimit])
            }
            switch options.timingOptions.outputFormat {
                case .stdout:
                    print("=== \(options.symbolOutput.getSymbol(.Timer)) SLOWEST TESTS ===", .CyanBold)
                    for (idx, result) in sortedByTime.enumerated() {
                        // TODO: line up the lines, just generally clean up this output
                        print(
                            "\(idx + 1) | \(result.test.fullName) (\(result.passed ? "Succeeded\(result.skipped ? " - Skipped" : "")" : "Failed")): \(result.duration)",
                            result.passed ? .GreenBold : .RedBold
                        )
                    }
                case .csv:
                    let lines = "Suite,Name,Time (s),Passed\n" + sortedByTime
                        .map { "\($0.test.suite),\($0.test.name),\($0.duration),\($0.passed)" }.joined(separator: "\n")
                    FileManager.default.createFile(
                        atPath: options.timingOptions.outputPath,
                        contents: lines.data(using: .ascii)
                    )
                    print("Successfully output test times to \(options.timingOptions.outputPath)", .Cyan)
            }
        }
    }

    /// Returns true if the line indicated a completed test
    private func parseTestLine(_ line: String) throws -> Bool {
        // TODO: this whole function could use some refactoring
        if line.starts(with: "Test Case") && !line.contains("started") {
            var processedLine = line
            processedLine.removeFirst("Test Case '".count)
            let components = processedLine.split(separator: "'")
            guard let fullTestName = components.first else {
                throw TestParseError.unexpectedLineFormat("could not parse completion line: \(line)")
            }

            let test = try parseTestFromName(String(fullTestName), line: line)

            guard
                let timeString = processedLine.split(separator: "(").last?.split(separator: " ").first,
                let testDuration = Double(String(timeString))
            else {
                throw TestParseError.unexpectedLineFormat("Could not parse time from line: \(line)")
            }

            if line.contains("passed") {
                testResults[test] = TestResult(
                    test: test,
                    passed: true,
                    skipped: false,
                    errors: [],
                    duration: .seconds(testDuration)
                )
                return true
            }
            if line.contains("failed") {
                testResults[test]?.duration = .seconds(testDuration)
                return false
            }
            // FIXME: still slightly hacky but less prone to collision - XCT fails output the file name on the line so use that
            // for more uniqueness guarantees
            return false
        } else if line.contains("error:") && line.contains(".swift") {
            // Parse and store the error reason
            let errorComponents = line.split(separator: "error:")
            guard let errorLocation = errorComponents.first, let testAndFail = errorComponents.last else {
                throw TestParseError.unexpectedLineFormat("Could not parse error line: \(line)")
            }

            var location = String(errorLocation.trimmingCharacters(in: [":", " "]))
            location.removeFirst(packagePathPrefix.count)
            let failureComponents = testAndFail.split(separator: ":")
            guard
                let testName = failureComponents.first?.trimmingCharacters(in: .whitespaces),
                let failure = failureComponents.last
            else {
                throw TestParseError
                    .unexpectedLineFormat("Could not parse error line, failed to pull test failure: \(line)")
            }

            let test = try parseTestFromName(testName, line: line)
            testResults[
                test,
                default: TestResult(test: test, passed: false, skipped: false, errors: [], duration: .seconds(0))
            ].errors
                .append((
                    location,
                    String(failure.trimmingCharacters(in: .init(charactersIn: "- ")))
                ))
            return false
        } else if line.contains("skipped") && line.contains(".swift") {
            // Parse and store the skip reason
            // The spaces are important here and this is quite beholden to spm output formatting, just be aware
            let skippedComponents = line.split(separator: " : ")
            guard let fullTestName = skippedComponents.first?.split(separator: ": ").last else {
                throw TestParseError.unexpectedLineFormat("Could not parse skipped test identifier from line: \(line)")
            }
            let test = try parseTestFromName(String(fullTestName), line: line)
            guard let skipReason = skippedComponents.last?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw TestParseError.unexpectedLineFormat("Could not parse skip reason from line: \(line)")
            }
            testResults[test] = TestResult(
                test: test,
                passed: true,
                skipped: true,
                errors: [("", skipReason)],
                duration: .seconds(0)
            )
            return false
        }
        return false
    }
}

private func parseTestFromName(_ testName: String, line: String) throws -> Test {
    let nameComponents = testName.split(separator: ".")
    guard let testSuite = nameComponents.first, let testName = nameComponents.last else {
        throw TestParseError.unexpectedLineFormat("could not parse test name from line: \(line)")
    }
    return Test(suite: String(testSuite), name: String(testName))
}

enum TestParseError: Error {
    case unexpectedLineFormat(String)
    case notSwiftPackage
    case buildFailure
}
