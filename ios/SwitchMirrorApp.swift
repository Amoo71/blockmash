import SwiftUI
import ScreenCaptureKit
import AVFoundation

@main
struct SwitchMirrorApp: App {
    var body: some Scene {
        WindowGroup { CaptureView() }
    }
}

@MainActor
final class CaptureModel: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published var status = "Idle"
    @Published var frameCount = 0
    private var stream: SCStream?

    func startCapture() async {
        guard SCShareableContent.currentProcessShareableContent != nil else {
            // ScreenCaptureKit availability is OS-dependent; request content below.
            status = "Requesting screen access…"
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { status = "No display available"; return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 1920
                config.height = 1080
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 3
                let capture = SCStream(filter: filter, configuration: config, delegate: self)
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "SwitchMirror.frames"))
                try await capture.startCapture()
                stream = capture
                status = "Capturing locally · no stream sent"
            } catch {
                status = "Capture failed: \(error.localizedDescription)"
            }
            return
        }
        status = "Screen capture API availability check"
    }

    func stopCapture() async {
        do { try await stream?.stopCapture() } catch { status = "Stop failed: \(error.localizedDescription)" }
        stream = nil
        status = "Stopped"
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        Task { @MainActor in frameCount += 1 }
        // TODO: encode frames and feed a transport video track.
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in status = "Capture stopped: \(error.localizedDescription)" }
    }
}

struct CaptureView: View {
    @StateObject private var model = CaptureModel()
    var body: some View {
        VStack(spacing: 18) {
            Text("SwitchMirror").font(.largeTitle.bold())
            Text(model.status).multilineTextAlignment(.center)
            Text("Frames received: \(model.frameCount)")
            Button("Start screen capture") { Task { await model.startCapture() } }
                .buttonStyle(.borderedProminent)
            Button("Stop capture") { Task { await model.stopCapture() } }
                .buttonStyle(.bordered)
            Text("Experimental local capture only. No video is transmitted.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding()
    }
}
