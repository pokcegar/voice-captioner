@preconcurrency import AVFoundation
import Foundation

public enum AudioChunkExtractorError: Error, Equatable, CustomStringConvertible {
    case missingSource(URL)
    case invalidRange(id: String, sourceStart: TimeInterval, sourceEnd: TimeInterval)
    case unreadableSource(URL, String)
    case conversionFailed(String)
    case writeFailed(URL, String)

    public var description: String {
        switch self {
        case let .missingSource(url):
            return "Missing chunk source: \(url.path)"
        case let .invalidRange(id, sourceStart, sourceEnd):
            return "Invalid source range for \(id): \(sourceStart)-\(sourceEnd)"
        case let .unreadableSource(url, message):
            return "Unreadable source \(url.path): \(message)"
        case let .conversionFailed(message):
            return "Chunk conversion failed: \(message)"
        case let .writeFailed(url, message):
            return "Unable to write chunk \(url.path): \(message)"
        }
    }
}

public struct AudioChunkExtractor: Sendable {
    public var targetSampleRate: Double
    public var targetChannelCount: AVAudioChannelCount

    public init(targetSampleRate: Double = 16_000, targetChannelCount: AVAudioChannelCount = 1) {
        self.targetSampleRate = targetSampleRate
        self.targetChannelCount = targetChannelCount
    }

    public func extract(_ chunks: inout [AudioChunkWorkItem], meeting: MeetingFolder) throws {
        try FileManager.default.createDirectory(at: meeting.chunksDirectory, withIntermediateDirectories: true)
        for index in chunks.indices where chunks[index].status != .complete {
            do {
                try extract(chunks[index], meeting: meeting)
            } catch {
                chunks[index].status = .failed
                chunks[index].retryCount += 1
                chunks[index].lastError = String(describing: error)
            }
        }
    }

    public func extract(_ chunk: AudioChunkWorkItem, meeting: MeetingFolder) throws {
        let sourceURL = meeting.rootURL.appending(path: chunk.sourceRelativePath, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AudioChunkExtractorError.missingSource(sourceURL)
        }
        guard chunk.sourceEnd > chunk.sourceStart, chunk.sourceStart >= 0 else {
            throw AudioChunkExtractorError.invalidRange(id: chunk.id, sourceStart: chunk.sourceStart, sourceEnd: chunk.sourceEnd)
        }

        let chunkURL = meeting.rootURL.appending(path: chunk.chunkRelativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: chunkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: chunkURL.path) {
            try FileManager.default.removeItem(at: chunkURL)
        }

        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw AudioChunkExtractorError.unreadableSource(sourceURL, String(describing: error))
        }

        let sourceFormat = sourceFile.processingFormat
        let sourceSampleRate = sourceFormat.sampleRate
        let startFrame = AVAudioFramePosition((chunk.sourceStart * sourceSampleRate).rounded(.down))
        let endFrame = min(
            AVAudioFramePosition((chunk.sourceEnd * sourceSampleRate).rounded(.up)),
            sourceFile.length
        )
        guard endFrame > startFrame else {
            throw AudioChunkExtractorError.invalidRange(id: chunk.id, sourceStart: chunk.sourceStart, sourceEnd: chunk.sourceEnd)
        }

        sourceFile.framePosition = startFrame
        let frameCount = AVAudioFrameCount(endFrame - startFrame)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw AudioChunkExtractorError.conversionFailed("Unable to allocate input buffer")
        }
        try sourceFile.read(into: inputBuffer, frameCount: frameCount)
        try writeWhisperCompatibleWAV(inputBuffer, to: chunkURL)
    }

    private func writeWhisperCompatibleWAV(_ inputBuffer: AVAudioPCMBuffer, to url: URL) throws {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: true
        ) else {
            throw AudioChunkExtractorError.conversionFailed("Unable to create 16 kHz mono output format")
        }
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
            throw AudioChunkExtractorError.conversionFailed("Unable to create audio converter")
        }

        let outputCapacity = AVAudioFrameCount(
            ceil(Double(inputBuffer.frameLength) * targetSampleRate / inputBuffer.format.sampleRate) + 128
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw AudioChunkExtractorError.conversionFailed("Unable to allocate output buffer")
        }

        let inputState = ConverterInputState(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputState.suppliedInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputState.suppliedInput = true
            outStatus.pointee = .haveData
            return inputState.buffer
        }
        if let conversionError {
            throw AudioChunkExtractorError.conversionFailed(conversionError.localizedDescription)
        }
        guard status != .error else {
            throw AudioChunkExtractorError.conversionFailed("AVAudioConverter returned error status")
        }

        do {
            let outputFile = try AVAudioFile(forWriting: url, settings: outputFormat.settings)
            try outputFile.write(from: outputBuffer)
        } catch {
            throw AudioChunkExtractorError.writeFailed(url, String(describing: error))
        }
    }
}


private final class ConverterInputState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var suppliedInput: Bool

    init(buffer: AVAudioPCMBuffer, suppliedInput: Bool = false) {
        self.buffer = buffer
        self.suppliedInput = suppliedInput
    }
}
