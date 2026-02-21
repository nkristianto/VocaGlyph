import Foundation

class Logger {
    static let shared = Logger()
    
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let logQueue = DispatchQueue(label: "com.vocaglyph.logger", qos: .utility)
    
    private init() {
        // Setup Date Formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Setup Log Directory: ~/.VocaGlyph/logs/
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let vocaGlyphDir = homeDirectory.appendingPathComponent(".VocaGlyph")
        let logsDir = vocaGlyphDir.appendingPathComponent("logs")
        
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("CRITICAL: Failed to create log directory: \(error)")
        }
        
        logFileURL = logsDir.appendingPathComponent("vocaglyph.log")
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
        
        self.info("=== Application Started ===")
    }
    
    func info(_ message: String) {
        log(level: "INFO ", message: message)
    }
    
    func error(_ message: String) {
        log(level: "ERROR", message: message)
    }
    
    func debug(_ message: String) {
        #if DEBUG
        log(level: "DEBUG", message: message)
        #endif
    }
    
    private func log(level: String, message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let formattedMessage = "[\(timestamp)] [\(level)] \(message)\n"
        
        // Print to Xcode console/Terminal for local developer debugging
        print(formattedMessage, terminator: "")
        
        // Write persistently to disk
        guard let data = formattedMessage.data(using: .utf8) else { return }
        
        logQueue.async {
            do {
                let fileHandle = try FileHandle(forWritingTo: self.logFileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } catch {
                print("CRITICAL: Failed to write to log file: \(error)")
            }
        }
    }
}
