// Peregrine.swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ArgumentParser
import Foundation
import Puppy
import SwiftCommand

@main
struct Peregrine: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A utility for clearer swift test output.",
        version: "0.4.0",
        subcommands: [Run.self, CountTests.self],
        defaultSubcommand: Run.self
    )

    struct GlobalOptions: ParsableArguments {
        @Argument(help: "Path to swift package.")
        var path: String = "."

        @Option(help: "Provide a specific swift toolchain executable. Default is to look in $PATH")
        var toolchain: String? = nil

        @Flag(
            name: .customLong("plain"),
            help: "Output symbols in plaintext (rather than nerd font symbols). Defaults to false."
        )
        var plaintextOutput: Bool = false

        @Flag(help: "Supress toolchain information & progress output")
        var quiet: Bool = false

        @Option(help: "Control Peregrine's log level.")
        var logLevel: LogLevel = .debug
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

        @Option(
            parsing: .remaining,
            help: ArgumentHelp(
                "Pass swift flags through to the underlying test invocation.",
                discussion: "Note that parallel testing may cause unexpected parsing behavior as spms xunit output is currently lacking."
            )
        )
        var swiftFlags: [String] = []

        mutating func run() async throws {
            // TODO: ? Potentially allow config by yaml in root of package - may be unnnecessary for so few options

            let logger = try configureLogging(options.logLevel)
            logger.info("Executing Tests")

            try Command.findInPath(withName: "clear")?.wait()
            try Command.findInPath(withName: "tput")?.addArgument("civis").wait()
            defer {
                tputCnorm()
            }

            if !options.quiet {
                print("=== PEREGRINE - EXECUTING TESTS ===", .CyanBold)
                try print(getSwiftVersion(), .Cyan)
            }
            let testOptions = TestOptions(
                toolchainPath: options.toolchain,
                packagePath: URL(fileURLWithPath: options.path, isDirectory: true).path,
                plaintextOutput: options.plaintextOutput,
                quietOutput: options.quiet,
                additionalSwiftFlags: swiftFlags,
                timingOptions: TestOptions.TestTimingOptions(
                    showTimes: showTimes,
                    count: longestTestCount,
                    outputFormat: longTestOutputFormat,
                    outputPath: longestTestOutputPath
                )
            )
            logger.debug("Running with options: \(testOptions)")
            let testRunner = PeregrineRunner(options: testOptions, logger: logger)
            try await handle {
                let tests = try await testRunner.listTests()
                let testResults = try await testRunner.runTests(tests: tests)
                try testRunner.output(results: testResults)
            }

            // only cleanup on fully successful run
            try cleanupLogFile(logger: logger)
        }

        private func getSwiftVersion() throws -> String {
            try "Toolchain Information:\n\((options.toolchain == nil ? Command.findInPath(withName: "swift") : Command(executablePath: .init(options.toolchain!)))?.addArgument("--version").waitForOutput().stdout ?? "Unknown")"
        }
    }

    struct CountTests: AsyncParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Flag(help: "Show output broken down by test suite")
        var groupBySuite: Bool = false

        // Thinking about a "compare by revision" option?
        mutating func run() async throws {
            let logger = try configureLogging(options.logLevel)
            try Command.findInPath(withName: "clear")?.wait()
            try Command.findInPath(withName: "tput")?.addArgument("civis").wait()
            defer {
                tputCnorm()
            }

            try await handle {
                print("=== PEREGRINE - COUNTING TESTS ===", .CyanBold)
                let tests = try await PeregrineRunner(options: TestOptions(
                    toolchainPath: options.toolchain,
                    packagePath: options.path,
                    plaintextOutput: options.plaintextOutput
                ), logger: logger).listTests()
                let testsBySuite = Dictionary(grouping: tests, by: \.suite)
                print("Found \(tests.count) total tests across \(testsBySuite.keys.count) Suites", .GreenBold)
                if groupBySuite {
                    print(String(repeating: "-", count: 50), .GreenBold)
                    print(
                        testsBySuite.sorted(by: { $0.value.count > $1.value.count })
                            .map { "\($0.key): \($0.value.count)" }
                            .joined(separator: "\n"),
                        .GreenBold
                    )
                }
            }

            // only cleanup on fully successful run
            try cleanupLogFile(logger: logger)
        }
    }
}

private func handle(_ peregrineOperation: () async throws -> Void) async throws {
    do {
        try await peregrineOperation()
    } catch let TestParseError.unexpectedLineFormat(errDetail) {
        print("""
        peregrine ran into an issue when running: \(errDetail)

        Please submit a bug report at https://github.com/GNMoseke/peregrine/issues
        Please include the logs found at /tmp/peregrine.log
        """, .RedBold)
        tputCnorm()
        Foundation.exit(4)
    } catch TestParseError.buildFailure {
        tputCnorm()
        Foundation.exit(1)
    } catch TestParseError.notSwiftPackage {
        print("Given path does not appear to be a swift package - no Package.swift file found.", .RedBold)
        tputCnorm()
        Foundation.exit(2)
    } catch PeregrineError.couldNotFindSwiftExecutable {
        print("peregrine could not find the swift executable in your path or at the given toolchain", .RedBold)
        tputCnorm()
        Foundation.exit(3)
    }
}

private func tputCnorm() {
    do {
        try Command.findInPath(withName: "tput")?.addArgument("cnorm").wait()
    } catch {
        print(
            "Peregrine ran into an error cleaning up. If your cursor is hidden, run `tput cnorm`.",
            .RedBold
        )
    }
}

enum PeregrineError: Error {
    case couldNotFindSwiftExecutable
}

extension LogLevel: ExpressibleByArgument {}
