import AVFoundation
import SwiftUI

struct RecordingSettingsView: View {
    let environment: AppEnvironment
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var permissions = PermissionsService.shared
    @State private var cameras: [AVCaptureDevice] = []

    var body: some View {
        Form {
            Section(String(localized: "Video")) {
                Picker(String(localized: "Frame rate"), selection: $settings.preferences.videoFrameRate) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
                Picker(String(localized: "Resolution limit"), selection: $settings.preferences.resolutionCap) {
                    ForEach(ResolutionCap.allCases) { cap in
                        Text(cap.displayName).tag(cap)
                    }
                }
                Text(String(localized: "Snaplet never upscales. A limit only applies when the source is larger."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(String(localized: "Show the pointer"), isOn: $settings.preferences.showCursorInRecording)
                Toggle(String(localized: "Highlight mouse clicks"), isOn: $settings.preferences.highlightMouseClicks)
                Text(String(localized: "Click highlighting is drawn by the system capture pipeline. Snaplet does not read keyboard input."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(String(localized: "Countdown"), selection: $settings.preferences.countdownSeconds) {
                    Text(String(localized: "Off")).tag(0)
                    Text("3s").tag(3)
                    Text("5s").tag(5)
                }
            }

            Section(String(localized: "Audio")) {
                Toggle(String(localized: "Record system audio"), isOn: $settings.preferences.recordSystemAudio)
                Toggle(String(localized: "Record microphone"), isOn: $settings.preferences.recordMicrophone)
                if settings.preferences.recordMicrophone {
                    PermissionRow(title: String(localized: "Microphone"),
                                  status: permissions.microphone,
                                  pane: .microphone)
                }
            }

            Section(String(localized: "Webcam overlay")) {
                Toggle(String(localized: "Include a webcam overlay"), isOn: $settings.preferences.webcamEnabled)
                if settings.preferences.webcamEnabled {
                    PermissionRow(title: String(localized: "Camera"),
                                  status: permissions.camera,
                                  pane: .camera)
                    Picker(String(localized: "Camera"), selection: cameraBinding) {
                        Text(String(localized: "Default")).tag(String?.none)
                        ForEach(cameras, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(String?.some(device.uniqueID))
                        }
                    }
                    Picker(String(localized: "Shape"), selection: $settings.preferences.webcamShape) {
                        ForEach(WebcamShape.allCases) { shape in
                            Text(shape.displayName).tag(shape)
                        }
                    }
                    Picker(String(localized: "Corner"), selection: $settings.preferences.webcamCorner) {
                        ForEach(OverlayCorner.allCases) { corner in
                            Text(corner.displayName).tag(corner)
                        }
                    }
                    VStack(alignment: .leading) {
                        Slider(value: $settings.preferences.webcamSizePercent, in: 0.12...0.40) {
                            Text(String(localized: "Size"))
                        }
                        Text(String(localized: "\(Int(settings.preferences.webcamSizePercent * 100))% of the video height"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "The overlay is composited into the exported file, not just shown on screen."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { cameras = CameraDevices.available() }
    }

    private var cameraBinding: Binding<String?> {
        Binding(get: { settings.preferences.webcamDeviceID },
                set: { settings.preferences.webcamDeviceID = $0 })
    }
}

enum CameraDevices {
    static func available() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                         mediaType: .video,
                                         position: .unspecified).devices
    }

    static func device(withID id: String?) -> AVCaptureDevice? {
        if let id, let match = available().first(where: { $0.uniqueID == id }) { return match }
        return available().first
    }
}
