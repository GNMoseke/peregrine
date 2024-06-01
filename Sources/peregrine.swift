import ArgumentParser
import Foundation
import SwiftCommand

// TODO: move this from a global
var tests: [Test] = []
@main
struct Peregrine: AsyncParsableCommand {
    @Argument
    var path: String = "."

    @Option(help: "Provide a specific swift toolchain path.")
    var toolchain: String = "/usr/bin/swift"

    @Option(help: "Execute tests in parallel")
    var parallel: Bool = false

    mutating func run() async throws {
        // TODO: allow direct passthrough of swift test options

        /* plan here is to:
        1. List tests with build
        2. Count tests from list output
        3. Run tests and monitor stdout, building progress bar as each test completes
        4. Clean up the output based on all sucess/which ones failed/etc
        5. Output nerdfont or raw
        */
        // Want to do junit xml output and parsing, options for showing longest running tests, etc
        print("=== PEREGRINE ===")
        try print(getSwiftVersion())
        try await runTests()
    }

    private func getSwiftVersion() throws -> String {
        try Command(executablePath: .init(toolchain)).addArgument("--version").waitForOutput().stdout
    }

    private func listTests() async throws -> [Test] {
        print(NerdFontIcons.Build.rawValue + " Building...", .CyanBold)
        let listProcess = try Command(executablePath: .init(toolchain))
            .addArguments(["test", "list", "--package-path", path])
            .setStdout(.pipe)
            .setStderr(.pipe)
            .spawn()

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
            tests.append(Test(target: String(testTarget), class: String(testClass), name: String(testName)))
        }
        return tests
    }

    private func runTests() async throws {
        let testCount = try await listTests().count
        let testProcess = try Command(executablePath: .init(toolchain))
            .addArguments(["test", "--package-path", path] + (parallel ? ["--parallel"] : []))
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
        for try await line in testProcess.stdout.lines {
            // FIXME: this is hacky and inefficient, just use a regex
            if line.starts(with: "Test Case") && line.contains("started at") {
                completeTests += 1
                if completeTests % stepSize == 0 {
                    progressBar = String(progressBar.dropLast())
                    progressBar.insert(Character(NerdFontIcons.FilledBlock.rawValue), at: progressBar.startIndex)
                    progressIndex += 1
                    print(progressBar, terminator: "\r")
                    fflush(nil)
                }
            }
            if line.contains("error:") {
                errorLines.append(line)
            }
        }
        print("\n")
        try testProcess.wait()
        if try await testProcess.status.terminatedSuccessfully {
            print(NerdFontIcons.Success.rawValue + " All Tests Passed!", .GreenBold)
        }
        else {
            print("=== FAILED TESTS ===", .RedBold)
            try print(processErrors(errorLines: errorLines), .RedBold)
        }
    }
}

/// This relies heavily on the output format from swift test remaining the same, I'd like to parse xunit here
/// but spm's xunit output doesn't give valuable information: https://github.com/apple/swift-package-manager/issues/7622
func processErrors(errorLines: [String]) throws -> String {
    var errorsByTest = [Test: [String]]()
    for line in errorLines {
        // FIXME: so many force unwraps
        let failure = line.split(separator: "error:").last!
        let failureComponents = failure.split(separator: ":")
        let testIdentifierComponents = failureComponents.first?.split(separator: ".")
        let testClass = testIdentifierComponents?.first?.trimmingCharacters(in: .whitespaces)
        let name = testIdentifierComponents?.last?.trimmingCharacters(in: .whitespaces)
        let test = tests.first(where: { $0.class == testClass && $0.name == name })!
        errorsByTest[test, default: []].append(String(failureComponents.last!))
    }
    // TODO: include file and line here too
    var processed = ""
    for (test, errors) in errorsByTest {
        processed += NerdFontIcons.Failure.rawValue + " \(test.fullName):\n"
        processed += errors.map { "  \(NerdFontIcons.RightArrow.rawValue) \($0)"}.joined(separator: "\n")
    }
    return processed
}


func print(_ str: String, _ color: TextColor) {
    print(color.rawValue + str + "\u{001B}[0m")
}

enum TextColor: String {
    case GreenBold = "\u{001B}[0;32;1m"
    case RedBold =  "\u{001B}[0;31;1m"
    case CyanBold = "\u{001B}[0;36;1m"
}

enum NerdFontIcons: String {
    case ErlenmeyerFlask = "󰂓"
    case Build = "󱌣"
    case Failure = ""
    case Success = ""
    case RightArrow = "󱞩"
    // not technically nerd font icons but putting here
    case FilledBlock = "█"
    case LightlyShadedBlock = "░"
}

struct Test: Codable, Hashable {
    let target: String
    let `class`: String
    let name: String

    var fullName: String {
        get {
        "\(target).\(`class`)/\(name)"
        }
    }
}
