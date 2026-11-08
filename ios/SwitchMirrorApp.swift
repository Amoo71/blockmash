import SwiftUI
import AVFoundation
import CoreMedia
@preconcurrency import ScreenCaptureKit

@main
struct SwitchMirrorApp: App {
    var body: some Scene {
        WindowGroup { CaptureView() }
    }
}

@MainActor
final class CaptureModel: NSObject, ObservableObject {
    @Published var status = "Ready"
    @Published var frameCount = 0

    private let picker = SCContentSharingPicker.shared
    private var stream: SCStream?

    func presentScreenPicker() {
        guard #available(iOS 27.0, *) else {
            status = "Full-screen capture requires iOS 27 or later."
            return
        }
        guard picker.isAvailable else {
            status = "Screen capture is unavailable on this device."
            return
        }
        picker.add(self)
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        picker.isActive = true
        status = "Choose Entire Screen in the system picker…"
        picker.present()
    }

    func stopCapture() async {
        do {
            try await stream?.stopCapture()
        } catch {
            status = "Stop failed: \(error.localizedDescription)"
        }
        stream = nil
        picker.isActive = false
        picker.remove(self)
        status = "Stopped"
    }

    func startCapture(with filter: SCContentFilter) async {
        do {
            if let stream {
                try? await stream.stopCapture()
            }
            let configuration = SCStreamConfiguration()
            configuration.width = 1920
            configuration.height = 1080
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 3
            let newStream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "SwitchMirror.capture"))
            try await newStream.startCapture()
            stream = newStream
            status = "Screen captured locally · transport not connected"
        } catch {
            status = "Capture failed: \(error.localizedDescription)"
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in
            await self.startCapture(with: filter)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.status = "Screen selection cancelled" }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.status = "Picker failed: \(error.localizedDescription)" }
    }
}

extension CaptureModel: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }
        Task { @MainActor in self.frameCount += 1 }
        // TODO: encode sample buffers and send them to the SwitchMirror relay.
    }
}

struct CaptureView: View {
    @StateObject private var model = CaptureModel()

    var body: some View {
        VStack(spacing: 18) {
            Text("SwitchMirror").font(.largeTitle.bold())
            Text(model.status).multilineTextAlignment(.center)
            Text("Captured frames: \(model.frameCount)")
            Button("Share Entire Screen") { model.presentScreenPicker() }
                .buttonStyle(.borderedProminent)
            Button("Stop Sharing") { Task { await model.stopCapture() } }
                .buttonStyle(.bordered)
            Text("iOS 27+ · Experimental capture preview only. Video transport to the Switch is not connected yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
