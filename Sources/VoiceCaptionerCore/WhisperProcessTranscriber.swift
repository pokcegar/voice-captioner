import Darwin
import Foundation

public enum WhisperProcessOutputFormat: String, Equatable, Sendable {
    case whisperJSON = "whisper.cpp -oj JSON"
}

public struct WhisperProcessConfiguration: Equatable, Sendable {
    public var executableURL: URL
    public var timeoutSeconds: TimeInterval
    public var outputFormat: WhisperProcessOutputFormat

    public init(
        executableURL: URL,
        timeoutSeconds: TimeInterval = 120,
        outputFormat: WhisperProcessOutputFormat = .whisperJSON
    ) {
        self.executableURL = executableURL
        self.timeoutSeconds = timeoutSeconds
        self.outputFormat = outputFormat
    }
}

public enum WhisperProcessError: Error, Equatable {
    case executableMissing(URL)
    case modelMissing(URL)
    case chunkMissing(URL)
    case timedOut(seconds: TimeInterval, stdout: String, stderr: String)
    case cancelled(stdout: String, stderr: String)
    case failed(exitCode: Int32, stdout: String, stderr: String)
    case missingJSONOutput(URL, stdout: String, stderr: String)
    case malformedJSON(URL, message: String)
}

public final class WhisperProcessTranscriber: TranscriptionProvider, @unchecked Sendable {
    private let configuration: WhisperProcessConfiguration

    public init(configuration: WhisperProcessConfiguration) {
        self.configuration = configuration
    }

    public func transcribe(chunk: AudioChunk, model: WhisperModel) async throws -> [TranscriptSegment] {
        guard FileManager.default.isExecutableFile(atPath: configuration.executableURL.path) else {
            throw WhisperProcessError.executableMissing(configuration.executableURL)
        }
        guard FileManager.default.fileExists(atPath: model.localPath.path) else {
            throw WhisperProcessError.modelMissing(model.localPath)
        }
        guard FileManager.default.fileExists(atPath: chunk.url.path) else {
            throw WhisperProcessError.chunkMissing(chunk.url)
        }

        let outputPrefix = chunk.url.deletingLastPathComponent()
            .appending(path: "\(chunk.url.deletingPathExtension().lastPathComponent)-whisper-output", directoryHint: .notDirectory)
        let jsonURL = outputPrefix.appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            try FileManager.default.removeItem(at: jsonURL)
        }

        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = [
            "-m", model.localPath.path,
            "-f", chunk.url.path,
            "-oj",
            "-of", outputPrefix.path
        ]

        let result = try await ProcessRunner.run(process, timeoutSeconds: configuration.timeoutSeconds)
        guard result.exitCode == 0 else {
            throw WhisperProcessError.failed(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
        }
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw WhisperProcessError.missingJSONOutput(jsonURL, stdout: result.stdout, stderr: result.stderr)
        }

        do {
            return try WhisperJSONParser.parse(url: jsonURL, track: chunk.track)
        } catch let error as WhisperProcessError {
            throw error
        } catch {
            throw WhisperProcessError.malformedJSON(jsonURL, message: String(describing: error))
        }
    }
}

private struct ProcessResult: Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private final class PipeCollector: @unchecked Sendable {
    let pipe = Pipe()
    private let lock = NSLock()
    private var data = Data()

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let available = handle.availableData
            guard !available.isEmpty else { return }
            self?.append(available)
        }
    }

    func finish() -> String {
        pipe.fileHandleForReading.readabilityHandler = nil
        append(pipe.fileHandleForReading.readDataToEndOfFile())
        lock.lock()
        let output = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()
        return output
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
}

private final class ManagedProcess: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var terminationRequested = false

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        lock.lock()
        terminationRequested = true
        let shouldTerminate = process.isRunning
        let pid = shouldTerminate ? process.processIdentifier : 0
        lock.unlock()

        guard shouldTerminate else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stillRunning = self.process.isRunning
            self.lock.unlock()
            if stillRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    func wasTerminationRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminationRequested
    }
}

private enum ProcessRunner {
    static func run(_ process: Process, timeoutSeconds: TimeInterval) async throws -> ProcessResult {
        let managed = ManagedProcess(process)
        let stdout = PipeCollector()
        let stderr = PipeCollector()
        stdout.start()
        stderr.start()
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe

        try process.run()

        return try await withTaskCancellationHandler {
            try await waitForExit(
                managed,
                stdout: stdout,
                stderr: stderr,
                timeoutSeconds: timeoutSeconds
            )
        } onCancel: {
            managed.terminate()
        }
    }

    private static func waitForExit(
        _ managed: ManagedProcess,
        stdout: PipeCollector,
        stderr: PipeCollector,
        timeoutSeconds: TimeInterval
    ) async throws -> ProcessResult {
        let start = Date()
        while managed.process.isRunning {
            if Task.isCancelled {
                managed.terminate()
                managed.process.waitUntilExit()
                throw WhisperProcessError.cancelled(
                    stdout: stdout.finish(),
                    stderr: stderr.finish()
                )
            }
            if timeoutSeconds > 0, Date().timeIntervalSince(start) >= timeoutSeconds {
                managed.terminate()
                managed.process.waitUntilExit()
                throw WhisperProcessError.timedOut(
                    seconds: timeoutSeconds,
                    stdout: stdout.finish(),
                    stderr: stderr.finish()
                )
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        managed.process.waitUntilExit()
        if Task.isCancelled || managed.wasTerminationRequested() {
            throw WhisperProcessError.cancelled(
                stdout: stdout.finish(),
                stderr: stderr.finish()
            )
        }
        return ProcessResult(
            exitCode: managed.process.terminationStatus,
            stdout: stdout.finish(),
            stderr: stderr.finish()
        )
    }
}

public enum WhisperJSONParser {
    public static func parse(url: URL, track: AudioTrackKind) throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: url)
        do {
            let decoded = try JSONDecoder().decode(WhisperOutput.self, from: data)
            return decoded.transcription.compactMap { item in
                guard let start = item.timestamps.from.seconds, let end = item.timestamps.to.seconds else { return nil }
                return TranscriptSegment(
                    id: UUID().uuidString,
                    sourceTrack: track,
                    speakerLabel: track == .system ? "Remote" : "Local",
                    start: start,
                    end: end,
                    text: item.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isDraft: true
                )
            }
        } catch {
            throw WhisperProcessError.malformedJSON(url, message: String(describing: error))
        }
    }

    private struct WhisperOutput: Decodable {
        var transcription: [TranscriptionItem]
    }

    private struct TranscriptionItem: Decodable {
        var timestamps: Timestamps
        var text: String
    }

    private struct Timestamps: Decodable {
        var from: WhisperTimestamp
        var to: WhisperTimestamp
    }

    private enum WhisperTimestamp: Decodable, Equatable {
        case seconds(TimeInterval)
        case formatted(String)
        case missing

        var seconds: TimeInterval? {
            switch self {
            case .seconds(let value):
                return value
            case .formatted(let value):
                return Self.parseFormatted(value)
            case .missing:
                return nil
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .missing
            } else if let seconds = try? container.decode(TimeInterval.self) {
                self = .seconds(seconds)
            } else {
                self = .formatted(try container.decode(String.self))
            }
        }

        private static func parseFormatted(_ value: String) -> TimeInterval? {
            let parts = value.split(separator: ":")
            guard parts.count == 3,
                  let hours = TimeInterval(parts[0]),
                  let minutes = TimeInterval(parts[1])
            else { return nil }
            let secondText = parts[2].replacingOccurrences(of: ",", with: ".")
            guard let seconds = TimeInterval(secondText) else { return nil }
            return hours * 3_600 + minutes * 60 + seconds
        }
    }
}
