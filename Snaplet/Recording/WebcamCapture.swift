import AVFoundation
import CoreVideo

/// Runs the camera and keeps the most recent frame available.
///
/// The compositor pulls the latest frame when a screen frame arrives, which
/// keeps the overlay locked to the screen timeline instead of drifting.
final class WebcamCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "app.snaplet.webcam")
    private let lock = NSLock()
    private var latest: CVPixelBuffer?

    private(set) var isRunning = false

    /// Starts the camera. Throws when the device cannot be opened; the caller
    /// decides whether to continue without an overlay.
    func start(deviceID: String?) throws {
        guard let device = CameraDevices.device(withID: deviceID) else {
            throw SnapletError.recordingSetupFailed("no camera available")
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw SnapletError.recordingSetupFailed("camera input rejected")
            }
            session.addInput(input)
        } catch let error as SnapletError {
            session.commitConfiguration()
            throw error
        } catch {
            session.commitConfiguration()
            throw SnapletError.recordingSetupFailed(error.localizedDescription)
        }

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw SnapletError.recordingSetupFailed("camera output rejected")
        }
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        session.stopRunning()
        output.setSampleBufferDelegate(nil, queue: nil)
        isRunning = false
        lock.lock()
        latest = nil
        lock.unlock()
    }

    var latestFrame: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = sampleBuffer.imageBuffer else { return }
        lock.lock()
        latest = buffer
        lock.unlock()
    }
}
