import ArgumentParser
import Foundation
import SwiftCommand

@main
struct Peregrine: AsyncParsableCommand {
    @Argument
    var path: String = "."

    @Option(help: "Provide a specific swift toolchain path.")
    var toolchain: String = "/usr/bin/swift"

    @Option(help: "Execute tests in parallel")
    var parallel: Bool = false

    @Flag(help: "Output a list of the longest-running tests")
    var showLongest: Bool = false

    @Option(help: "change the count of longest test output. A value of -1 indicates that all tests should be shown.")
    var longestTestCount: Int = 10

    // Again, this should be handeld with xunit, but the spm xunit output is severely lacking
    @Option(help: "Control the output format for long tests")
    var longTestOutputFormat: LongTestOutputFormat = .stdout

    mutating func run() async throws {
        // TODO: allow direct passthrough of swift test options

        // Want to do junit xml output and parsing, options for showing longest running tests, etc
        print("=== PEREGRINE ===")
        try print(getSwiftVersion())
        let testOptions = TestOptions(parallel: parallel, generateXunit: false, toolchainPath: toolchain, packagePath: path)
        let testRunner = PeregrineRunner(options: testOptions)
        let tests = try await testRunner.listTests()
        let testResults = try await testRunner.runTests(tests: tests)
        try testRunner.output(results: testResults)
    }

    private func getSwiftVersion() throws -> String {
        try Command(executablePath: .init(toolchain)).addArgument("--version").waitForOutput().stdout
    }
}
