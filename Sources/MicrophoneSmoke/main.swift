import Foundation
import VoiceCaptionerCore

@main
struct MicrophoneSmoke {
    static func main() async throws {
        let output = URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: ".tmp/capture-smoke/microphone.wav")
        let recorder = MicrophoneRecorder()
        try recorder.start(outputURL: output)
        try await Task.sleep(for: .seconds(2))
        let file = try await recorder.stop()
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        print("\(file.path)")
        print("bytes=\(size?.intValue ?? 0)")
    }
}
