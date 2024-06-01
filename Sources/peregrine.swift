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

    mutating func run() async throws {
        // TODO: allow direct passthrough of swift test options
        let swiftPath = URL(fileURLWithPath: toolchain)

        /* plan here is to:
        1. List tests with build
        2. Count tests from list output
        3. Run tests and monitor stdout, building progress bar as each test completes
        4. Clean up the output based on all sucess/which ones failed/etc
        5. Output nerdfont or raw
        */
        //try print(getSwiftVersion(swiftPath: swiftPath))
        try await print(runTests(swiftPath: swiftPath))
    }

    private func getSwiftVersion(swiftPath: URL) throws -> String {
        let swiftVersionProcess = Process()
        swiftVersionProcess.executableURL = swiftPath
        swiftVersionProcess.arguments = ["--version"]

        let stdoutPipe = Pipe()
        swiftVersionProcess.standardOutput = stdoutPipe

        try swiftVersionProcess.run()
        return String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private func runTests(swiftPath: URL) async throws -> String {
        print(swiftPath.path)
        let testProcess = try Command(executablePath: .init(swiftPath.path))
            .addArguments(["test", "--package-path", path] + (parallel ? ["--parallel"] : []))
            .setStdout(.pipe)
            .spawn()

        var completeTests = 0
        for try await _ in testProcess.stdout.lines {
            completeTests += 1
        }
        try testProcess.wait()
        print(completeTests)
        if try await testProcess.status.terminatedSuccessfully {
            return "All Tests Passed"
        }
            return "Failure"
    }
}
