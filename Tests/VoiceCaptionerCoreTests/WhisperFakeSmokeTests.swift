import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("Whisper fake smoke")
struct WhisperFakeSmokeTests {
    @Test func fakeWhisperBinaryProducesDraftSegmentWithoutRealModel() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "fake-whisper.sh")
        let model = root.appending(path: "fake-model.bin")
        let chunkURL = root.appending(path: "chunk.wav")
        try Data("model".utf8).write(to: model)
        try Data("chunk".utf8).write(to: chunkURL)
        try fakeWhisperScript().write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let transcriber = WhisperProcessTranscriber(
            configuration: WhisperProcessConfiguration(executableURL: executable, timeoutSeconds: 2)
        )
        let chunk = AudioChunk(
            track: .system,
            url: chunkURL,
            sourceStart: 4,
            sourceEnd: 6,
            timelineStart: 10,
            timelineEnd: 12
        )

        let segments = try await transcriber.transcribe(chunk: chunk, model: WhisperModel(name: "fake", localPath: model))

        #expect(segments.count == 1)
        #expect(segments[0].sourceTrack == .system)
        #expect(segments[0].speakerLabel == "Remote")
        #expect(segments[0].start == 0.25)
        #expect(segments[0].end == 0.75)
        #expect(segments[0].text == "fake text")
        #expect(segments[0].isDraft)
    }

    @Test func fakeWhisperBinaryMissingJSONReportsTypedError() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "fake-whisper-no-json.sh")
        let model = root.appending(path: "fake-model.bin")
        let chunkURL = root.appending(path: "chunk.wav")
        try Data("model".utf8).write(to: model)
        try Data("chunk".utf8).write(to: chunkURL)
        try "#!/bin/sh\necho no-json\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let transcriber = WhisperProcessTranscriber(
            configuration: WhisperProcessConfiguration(executableURL: executable, timeoutSeconds: 2)
        )
        let chunk = AudioChunk(track: .microphone, url: chunkURL, sourceStart: 0, sourceEnd: 1, timelineStart: 0, timelineEnd: 1)

        await #expect(throws: WhisperProcessError.self) {
            _ = try await transcriber.transcribe(chunk: chunk, model: WhisperModel(name: "fake", localPath: model))
        }
    }
}

private func fakeWhisperScript() -> String {
    """
    #!/bin/sh
    output_prefix=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-of" ]; then
        shift
        output_prefix="$1"
      fi
      shift
    done
    if [ -z "$output_prefix" ]; then
      echo "missing output prefix" >&2
      exit 2
    fi
    cat > "${output_prefix}.json" <<'JSON'
    {"transcription":[{"timestamps":{"from":0.25,"to":0.75},"text":" fake text "}]}
    JSON
    echo "fake whisper ok"
    exit 0
    """
}
