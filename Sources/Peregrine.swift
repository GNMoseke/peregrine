import ArgumentParser
import Foundation
import SwiftCommand

@main
struct Peregrine: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "A utility for clearer swift test output.", version: "0.1.0", subcommands: [Run.self, CountTests.self], defaultSubcommand: Run.self)
    struct GlobalOptions: ParsableArguments {
        @Argument(help: "Path to swift package.")
        var path: String = "."

        @Option(help: "Provide a specific swift toolchain path.")
        var toolchain: String = "/usr/bin/swift"

        @Flag(name: .customLong("plain"), help: "Output symbols in plaintext (rather than nerd font symbols). Defaults to false.")
        var plaintextOutput: Bool = false
    }
}

extension Peregrine {
    struct Run: AsyncParsableCommand {
        @OptionGroup var options: Peregrine.GlobalOptions

        @Flag(help: "Output a list of the tests by runtime, longest first")
        var showTimes: Bool = false

        @Option(help: "Change the count of longest test output. Defaults to all if this option is not specified.")
        var longestTestCount: Int? = nil

        // Again, this should be handled with xunit, but the spm xunit output is severely lacking
        @Option(help: "Control the output format for long tests")
        var longTestOutputFormat: LongTestOutputFormat = .stdout

        @Option(help: "Output path for longest test file. Ignored if output is set to stdout.")
        var longestTestOutputPath: String = "tests-by-time"

        @Option(parsing: .remaining, help: ArgumentHelp("Pass swift flags through to the underlying test invocation", discussion: "Note that parallel testing may cause unexpected parsing behavior as spms xunit output is currently lacking."))
        var swiftFlags: [String] = []

        mutating func run() async throws {
            // TODO: allow direct passthrough of swift test options
            // TODO: ? Potentially allow config by yaml in root of package - may be unnnecessary for so few options

            // Want to do junit xml output and parsing, options for showing longest running tests, etc
            print("=== PEREGRINE - EXECUTING TESTS ===", .CyanBold)
            try print(getSwiftVersion(), .Cyan)
            let testOptions = TestOptions(toolchainPath: options.toolchain, packagePath: options.path, plaintextOutput: options.plaintextOutput, additionalSwiftFlags: swiftFlags, timingOptions: TestOptions.TestTimingOptions(showTimes: showTimes, count: longestTestCount, outputFormat: longTestOutputFormat, outputPath: longestTestOutputPath))
            let testRunner = PeregrineRunner(options: testOptions)
            let tests = try await testRunner.listTests()
            let testResults = try await testRunner.runTests(tests: tests)
            try testRunner.output(results: testResults)
        }

        private func getSwiftVersion() throws -> String {
            try "Toolchain Information:\n\(Command(executablePath: .init(options.toolchain)).addArgument("--version").waitForOutput().stdout)"
        }
    }

    struct CountTests: AsyncParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Flag(help: "Show output broken down by test suite")
        var groupBySuite: Bool = false

        // Thinking about a "compare by revision" option?
        mutating func run() async throws {
            print("=== PEREGRINE - COUNTING TESTS ===", .CyanBold)
            let tests = try await PeregrineRunner(options: TestOptions(toolchainPath: options.toolchain, packagePath: options.path, plaintextOutput: options.plaintextOutput)).listTests()
            let testsBySuite = Dictionary(grouping: tests, by: \.suite)
            print("Found \(tests.count) total tests across \(testsBySuite.keys.count) Suites", .GreenBold)
            if groupBySuite {
                print(String(repeating: "-", count: 50), .GreenBold)
                print(testsBySuite.sorted(by: { $0.value.count > $1.value.count }).map { "\($0.key): \($0.value.count)" }.joined(separator: "\n"), .GreenBold)
            }
        }
    }
}