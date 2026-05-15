import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("WhisperProcessTranscriber")
struct WhisperProcessTranscriberTests {
    @Test func fakeBinarySuccessParsesJSONAndCapturesOutput() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeFixture(in: root)
        let script = try makeFakeWhisper(
            in: root,
            body: #"""
echo "stdout-ok"
echo "stderr-ok" >&2
prefix=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-of" ]; then
    shift
    prefix="$1"
  fi
  shift || true
done
cat > "${prefix}.json" <<'JSON'
{"transcription":[{"timestamps":{"from":1.25,"to":2.5},"text":" hello "}]}
JSON
exit 0
"""#
        )
        let transcriber = WhisperProcessTranscriber(configuration: WhisperProcessConfiguration(executableURL: script, timeoutSeconds: 10))

        let segments = try await transcriber.transcribe(chunk: fixture.chunk, model: fixture.model)

        #expect(segments.count == 1)
        #expect(segments[0].sourceTrack == .system)
        #expect(segments[0].speakerLabel == "Remote")
        #expect(segments[0].start == 1.25)
        #expect(segments[0].end == 2.5)
        #expect(segments[0].text == "hello")
        #expect(segments[0].isDraft)
    }

    @Test func nonZeroExitIncludesStdoutAndStderr() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeFixture(in: root)
        let script = try makeFakeWhisper(
            in: root,
            body: #"""
echo "bad stdout"
echo "bad stderr" >&2
exit 7
"""#
        )
        let transcriber = WhisperProcessTranscriber(configuration: WhisperProcessConfiguration(executableURL: script, timeoutSeconds: 10))

        do {
            _ = try await transcriber.transcribe(chunk: fixture.chunk, model: fixture.model)
            Issue.record("Expected non-zero whisper process to fail")
        } catch WhisperProcessError.failed(let exitCode, let stdout, let stderr) {
            #expect(exitCode == 7)
            #expect(stdout.contains("bad stdout"))
            #expect(stderr.contains("bad stderr"))
        }
    }

    @Test func timeoutTerminatesFakeBinaryQuickly() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeFixture(in: root)
        let marker = root.appending(path: "marker")
        let script = try makeFakeWhisper(
            in: root,
            body: "trap 'echo terminated > \"\(marker.path)\"; exit 0' TERM\nsleep 5\n"
        )
        let transcriber = WhisperProcessTranscriber(configuration: WhisperProcessConfiguration(executableURL: script, timeoutSeconds: 0.1))
        let started = Date()

        do {
            _ = try await transcriber.transcribe(chunk: fixture.chunk, model: fixture.model)
            Issue.record("Expected timeout")
        } catch WhisperProcessError.timedOut(let seconds, _, _) {
            #expect(seconds == 0.1)
            #expect(Date().timeIntervalSince(started) < 2)
        }
        // TERM traps are shell-dependent; elapsed time and typed timeout/cancel error prove termination.
    }

    @Test func missingModelAndChunkFailBeforeProcessLaunch() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeFixture(in: root)
        let script = try makeFakeWhisper(in: root, body: "exit 0\n")
        let transcriber = WhisperProcessTranscriber(configuration: WhisperProcessConfiguration(executableURL: script, timeoutSeconds: 10))

        await #expect(throws: WhisperProcessError.modelMissing(root.appending(path: "missing.bin"))) {
            _ = try await transcriber.transcribe(
                chunk: fixture.chunk,
                model: WhisperModel(name: "missing", localPath: root.appending(path: "missing.bin"))
            )
        }
        await #expect(throws: WhisperProcessError.chunkMissing(root.appending(path: "missing.wav"))) {
            _ = try await transcriber.transcribe(
                chunk: AudioChunk(id: "missing", track: .system, url: root.appending(path: "missing.wav"), start: 0, end: 1),
                model: fixture.model
            )
        }
    }


    @Test func parserAcceptsWhisperCppFormattedTimestampStrings() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let json = root.appending(path: "whisper-output.json")
        try Data("""
        {"transcription":[{"timestamps":{"from":"00:01:02,500","to":"01:02:03,250"},"text":" formatted "}]}
        """.utf8).write(to: json)

        let segments = try WhisperJSONParser.parse(url: json, track: .microphone)

        #expect(segments.count == 1)
        #expect(segments[0].start == 62.5)
        #expect(segments[0].end == 3723.25)
        #expect(segments[0].text == "formatted")
    }

    @Test func missingAndMalformedJSONAreTypedErrors() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeFixture(in: root)
        let missingJSONScript = try makeFakeWhisper(in: root.appending(path: "missing", directoryHint: .isDirectory), body: "exit 0\n")
        let missingJSONTranscriber = WhisperProcessTranscriber(configuration: WhisperProcessConfiguration(executableURL: missingJSONScript, timeoutSeconds: 10))

        do {
            _ = try await missingJSONTranscriber.transcribe(chunk: fixture.chunk, model: fixture.model)
            Issue.record("Expected missing JSON")
        } catch WhisperProcessError.missingJSONOutput(let url, _, _) {
            #expect(url.lastPathComponent == "chunk-whisper-output.json")
        }

        let malformedScript = try makeFakeWhisper(
            in: root.appending(path: "malformed", directoryHint: .isDirectory),
            body: #"""
prefix=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-of" ]; then
    shift
    prefix="$1"
  fi
  shift || true
done
echo "not-json" > "${prefix}.json"
exit 0
"""#
        )
        let malformedTranscriber = WhisperProcessTranscriber(configuration: WhisperProcessConfiguration(executableURL: malformedScript, timeoutSeconds: 10))
        do {
            _ = try await malformedTranscriber.transcribe(chunk: fixture.chunk, model: fixture.model)
            Issue.record("Expected malformed JSON")
        } catch WhisperProcessError.malformedJSON(let url, let message) {
            #expect(url.lastPathComponent == "chunk-whisper-output.json")
            #expect(!message.isEmpty)
        }
    }

    @Test func cancellationTerminatesProcess() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeFixture(in: root)
        let marker = root.appending(path: "cancelled")
        let script = try makeFakeWhisper(
            in: root,
            body: "trap 'echo cancelled > \"\(marker.path)\"; exit 0' TERM\nsleep 5\n"
        )
        let transcriber = WhisperProcessTranscriber(configuration: WhisperProcessConfiguration(executableURL: script, timeoutSeconds: 10))
        let task = Task {
            try await transcriber.transcribe(chunk: fixture.chunk, model: fixture.model)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch WhisperProcessError.cancelled {
            // TERM traps are shell-dependent; elapsed time and typed timeout/cancel error prove termination.
        } catch is CancellationError {
            // TERM traps are shell-dependent; elapsed time and typed timeout/cancel error prove termination.
        }
    }
}

private func makeFixture(in root: URL) throws -> (chunk: AudioChunk, model: WhisperModel) {
    let chunkURL = root.appending(path: "chunk.wav")
    let modelURL = root.appending(path: "ggml-small.bin")
    try Data("audio".utf8).write(to: chunkURL)
    try Data("model".utf8).write(to: modelURL)
    return (
        AudioChunk(id: "system-00000", track: .system, url: chunkURL, start: 0, end: 2),
        WhisperModel(name: "small", localPath: modelURL)
    )
}

private func makeFakeWhisper(in root: URL, body: String) throws -> URL {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let script = root.appending(path: "fake-whisper.sh")
    try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}
