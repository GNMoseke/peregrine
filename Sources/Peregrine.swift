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

        mutating func run() async throws {
            // TODO: allow direct passthrough of swift test options
            // TODO: ? Potentially allow config by yaml in root of package - may be unnnecessary for so few options

            // Want to do junit xml output and parsing, options for showing longest running tests, etc
            print("=== PEREGRINE - EXECUTING TESTS ===", .CyanBold)
            try print(getSwiftVersion(), .Cyan)
            let testOptions = TestOptions(toolchainPath: options.toolchain, packagePath: options.path)
            let testRunner = PeregrineRunner(options: testOptions)
            let tests = try await testRunner.listTests()
            let testResults = try await testRunner.runTests(tests: tests)
            try testRunner.output(results: testResults)
            if showTimes {
                var sortedByTime = testResults.tests.sorted(by: { $0.duration > $1.duration })
                if let countLimit = longestTestCount {
                    sortedByTime = Array(sortedByTime[0 ..< countLimit])
                }
                print("=== \(NerdFontIcons.Timer.rawValue) SLOWEST TESTS ===", .CyanBold)
                for (idx, result) in sortedByTime.enumerated() {
                    // TODO: line up the lines, just generally clean up this output
                    print("\(idx + 1) | \(result.test.fullName) (\(result.passed ? "Succeeded" : "Failed")): \(result.duration)", result.passed ? .GreenBold : .RedBold)
                }
            }
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
            let tests = try await PeregrineRunner(options: TestOptions(toolchainPath: options.toolchain, packagePath: options.path)).listTests()
            if groupBySuite {
                print("Found \(tests.count) total tests", .GreenBold)
                print(String(repeating: "-", count: 50), .GreenBold)
                print(Dictionary(grouping: tests, by: \.suite).sorted(by: { $0.value.count > $1.value.count }).map { "\($0.key): \($0.value.count)" }.joined(separator: "\n"), .GreenBold)
            } else {
                print("Found \(tests.count) tests", .GreenBold)
            }
        }
    }
}
