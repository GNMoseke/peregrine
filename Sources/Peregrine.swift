import ArgumentParser
import Foundation
import SwiftCommand

@main
struct Peregrine: AsyncParsableCommand {
    @Argument
    var path: String = "."

    @Option(help: "Provide a specific swift toolchain path.")
    var toolchain: String = "/usr/bin/swift"

    @Flag(help: "Output a list of the tests by runtime, longest first")
    var showTimes: Bool = false

    @Option(help: "Change the count of longest test output. Defaults to all.")
    var longestTestCount: Int? = nil

    // Again, this should be handled with xunit, but the spm xunit output is severely lacking
    @Option(help: "Control the output format for long tests")
    var longTestOutputFormat: LongTestOutputFormat = .stdout

    mutating func run() async throws {
        // TODO: allow direct passthrough of swift test options

        // Want to do junit xml output and parsing, options for showing longest running tests, etc
        print("=== PEREGRINE - EXECUTING TESTS ===", .CyanBold)
        try print(getSwiftVersion(), .Cyan)
        let testOptions = TestOptions(toolchainPath: toolchain, packagePath: path)
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
        "Toolchain Information:\n\(try Command(executablePath: .init(toolchain)).addArgument("--version").waitForOutput().stdout)"
    }
}
