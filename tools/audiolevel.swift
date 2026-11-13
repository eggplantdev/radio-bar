import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFoundation

final class Sink: NSObject, SCStreamOutput {
    var peak: Float = 0
    var buffers = 0
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        try? sb.withAudioBufferList { list, _ in
            for buf in list {
                guard let data = buf.mData else { continue }
                let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
                let p = data.bindMemory(to: Float.self, capacity: n)
                var sum: Float = 0
                for i in 0..<n { sum += p[i] * p[i] }
                if n > 0 { peak = max(peak, (sum / Float(n)).squareRoot()) }
            }
        }
        buffers += 1
    }
}

let bundleID = CommandLine.arguments[1]
let seconds = Double(CommandLine.arguments[2]) ?? 3
let sem = DispatchSemaphore(value: 0)
let sink = Sink()
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }),
              let display = content.displays.first else { print("app not found"); exit(2) }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.width = 2; cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: .global())
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
        try await stream.stopCapture()
        print(String(format: "rms=%.5f buffers=%d", sink.peak, sink.buffers))
    } catch { print("error: \(error)") }
    sem.signal()
}
sem.wait()
