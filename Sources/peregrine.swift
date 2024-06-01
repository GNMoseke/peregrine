import ArgumentParser
import Foundation

@main
struct Peregrine: ParsableCommand {
    @Argument
    var path: String = "."

    @Option(help: "Provide a specific swift toolchain path.")
    var toolchain: String = "/usr/bin/swift"

    @Option(help: "Execute tests in parallel")
    var parallel: Bool = false

    mutating func run() throws {
        let swiftPath = URL(fileURLWithPath: toolchain)

        try print(getSwiftVersion(swiftPath: swiftPath))
        try print(runTests(swiftPath: swiftPath))
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

    private func runTests(swiftPath: URL) throws -> String {
        let testProcess = Process()
        testProcess.executableURL = swiftPath
        testProcess.arguments = ["test", "--package-path", path]
        if parallel {
            testProcess.arguments?.append("--parallel")
        }


        let stdoutPipe = Pipe()
        testProcess.standardOutput = stdoutPipe

        try testProcess.run()
        return String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
