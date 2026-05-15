import Foundation
import VoiceCaptionerCore

@main
struct SystemAudioSmoke {
    static func main() async {
        let output = URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: ".tmp/capture-smoke/system.wav")
        let recorder = SystemAudioRecorder()
        do {
            try await recorder.start(outputURL: output)
            try await Task.sleep(for: .seconds(3))
            let file = try await recorder.stop()
            let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
            print("\(file.path)")
            print("bytes=\(size?.intValue ?? 0)")
        } catch {
            fputs("system-audio-smoke failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
