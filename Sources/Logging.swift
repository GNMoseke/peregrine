import Foundation
import Puppy

func configureLogging(_ level: LogLevel) throws -> Puppy {
    // TODO: logfile per project
    let logFormat = LogFormatter()
    let fileLogger = try FileLogger(
        "com.peregrine",
        logLevel: level,
        logFormat: logFormat,
        fileURL: URL(fileURLWithPath: "/tmp/peregrine.log").absoluteURL
    )
    var logger = Puppy()
    logger.add(fileLogger)
    return logger
}

func cleanupLogFile(logger: Puppy) throws {
    // ensure we fully flush anything left before removing the file
    _ = logger.flush()
    try FileManager.default.removeItem(at: URL(fileURLWithPath: "/tmp/peregrine.log").absoluteURL)
}

// pretty much the default from the readme in puppy for now
struct LogFormatter: LogFormattable {
    func formatMessage(
        _ level: LogLevel,
        message: String,
        tag _: String,
        function: String,
        file: String,
        line: UInt,
        swiftLogInfo _: [String: String],
        label _: String,
        date: Date,
        threadID: UInt64
    ) -> String {
        let fileName = fileName(file)
        let moduleName = moduleName(file)
        return "\(date) \(threadID) [\(level)] \(moduleName)/\(fileName)#L.\(line) \(function) \(message)"
            .colorize(level.color)
    }
}
