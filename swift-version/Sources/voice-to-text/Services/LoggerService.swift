import Foundation
import SwiftUI

// MARK: - Shared log directory

private let vocaGlyphLogsDir: URL = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".VocaGlyph").appendingPathComponent("logs")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

// MARK: - LogFile (reusable file-writing core)

/// A thread-safe, append-only log file.
private final class LogFile: @unchecked Sendable {
    let url: URL
    private let queue: DispatchQueue
    private let dateFormatter: DateFormatter

    init(filename: String, queueLabel: String) {
        url = vocaGlyphLogsDir.appendingPathComponent(filename)
        queue = DispatchQueue(label: queueLabel, qos: .utility)
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    func write(level: String, message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"

        // DEBUG is gated behind the debug-logging flag; INFO and ERROR always surface
        let isDebug = level == "DEBUG"
        let debugEnabled = UserDefaults.standard.bool(forKey: "enableDebugLogging")
        guard !isDebug || debugEnabled else { return }

        // Print to console
        print(line, terminator: "")

        // Write to disk
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [url] in
            do {
                let fh = try FileHandle(forWritingTo: url)
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } catch {
                print("CRITICAL: Failed to write to \(url.lastPathComponent): \(error)")
            }
        }
    }

    func clear() {
        queue.async { [url] in
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Logger (general app + transcription logs → vocaglyph.log)

class Logger {
    static let shared = Logger()

    private let file = LogFile(
        filename: "vocaglyph.log",
        queueLabel: "com.vocaglyph.logger"
    )

    private init() {
        info("=== Application Started ===")
    }

    func info(_ message: String)  { file.write(level: "INFO ", message: message) }
    func error(_ message: String) { file.write(level: "ERROR", message: message) }
    func debug(_ message: String) { file.write(level: "DEBUG", message: message) }

    func clearLogs() { file.clear() }
    func getLogFileURL() -> URL  { file.url }
}

// MARK: - PostProcessingLogger (API / local-model logs → postprocessing.log)

/// Dedicated logger for post-processing engines.
/// Writes to `~/.VocaGlyph/logs/postprocessing.log` independently of the main log.
class PostProcessingLogger {
    static let shared = PostProcessingLogger()

    private let file = LogFile(
        filename: "postprocessing.log",
        queueLabel: "com.vocaglyph.postprocessing.logger"
    )

    private init() {}

    func info(_ message: String)  { file.write(level: "INFO ", message: message) }
    func error(_ message: String) { file.write(level: "ERROR", message: message) }
    func debug(_ message: String) { file.write(level: "DEBUG", message: message) }

    func clearLogs() { file.clear() }
    func getLogFileURL() -> URL  { file.url }
}
