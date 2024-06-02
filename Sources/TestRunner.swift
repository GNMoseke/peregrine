import Foundation
import SwiftCommand

struct TestRunOutput {
    let success: Bool
    let tests: [Test]
    let errorLines: [String]?
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
    let target: String
    let `class`: String
    let name: String
    let timeToRun: Duration

    var fullName: String {
        "\(target).\(`class`)/\(name)"
    }
}

protocol TestRunner {
    var options: TestOptions { get }
    func listTests() async throws -> [Test]
    func runTests(tests: [Test]) async throws -> TestRunOutput
    func output(results: TestRunOutput) throws
}

struct PeregrineRunner: TestRunner {
    let options: TestOptions

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
            tests.append(Test(target: String(testTarget), class: String(testClass), name: String(testName), timeToRun: .seconds(0)))
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

        let progressBarCharacterLength = 30
        let stepSize: Int = testCount / progressBarCharacterLength
        var completeTests = 0
        var progressIndex = 0
        var progressBar = String(repeating: NerdFontIcons.LightlyShadedBlock.rawValue, count: progressBarCharacterLength)
        print(progressBar, terminator: "\r")
        fflush(nil)
        var errorLines = [String]()
        var backtraceLines = [String]()
        var collectBacktrace = false
        // TODO: clean this up, very heavy-handed processing
        for try await line in testProcess.stdout.lines {
            if collectBacktrace {
                backtraceLines.append(line)
            }
            // FIXME: this is hacky and inefficient, just use a regex
            else if line.starts(with: "Test Case") && line.contains("started at") {
                completeTests += 1
                if completeTests % stepSize == 0 {
                    progressBar = String(progressBar.dropLast())
                    progressBar.insert(Character(NerdFontIcons.FilledBlock.rawValue), at: progressBar.startIndex)
                    progressIndex += 1
                    print(progressBar, terminator: "\r")
                    fflush(nil)
                }
            } else if line.contains("Fatal error:") {
                backtraceLines.append(line)
                collectBacktrace = true
            } else if line.contains("error:") {
                errorLines.append(line)
            }
        }
        print("\n")
        try testProcess.wait()
        if try await testProcess.status.terminatedSuccessfully {
            return TestRunOutput(success: true, tests: tests, errorLines: nil, backtraceLines: nil)
        } else {
            return TestRunOutput(success: false, tests: tests, errorLines: errorLines.isEmpty ? nil : errorLines, backtraceLines: backtraceLines.isEmpty ? nil : backtraceLines)
        }
    }

    func output(results: TestRunOutput) throws {
        let processedOutput = try processOutput(testOutput: results)
        print(processedOutput.output, processedOutput.color)
    }
}
