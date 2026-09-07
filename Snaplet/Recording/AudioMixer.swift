import AVFoundation

/// Sums a secondary audio stream into a primary one on a shared timeline.
///
/// The primary stream (usually system audio) drives the output clock. Secondary
/// samples are buffered by presentation time and consumed as the primary
/// advances, so microphone and system audio stay in sync instead of drifting.
final class AudioMixer {

    private let format: AVAudioFormat
    private var pending: [(pts: CMTime, buffer: AVAudioPCMBuffer)] = []
    private let lock = NSLock()
    /// Never let the queue grow without bound if one source stalls.
    private let maximumBufferedSeconds: Double = 2

    init(format: AVAudioFormat) {
        self.format = format
    }

    func enqueueSecondary(_ sampleBuffer: CMSampleBuffer) {
        guard let buffer = AudioConversion.pcmBuffer(from: sampleBuffer, targetFormat: format) else { return }
        let pts = sampleBuffer.presentationTimeStamp
        lock.lock()
        pending.append((pts, buffer))
        // Drop the oldest data if the primary stream stops consuming.
        var total = 0.0
        for entry in pending {
            total += Double(entry.buffer.frameLength) / format.sampleRate
        }
        while total > maximumBufferedSeconds, let first = pending.first {
            total -= Double(first.buffer.frameLength) / format.sampleRate
            pending.removeFirst()
        }
        lock.unlock()
    }

    /// Returns `primary` with any overlapping secondary audio summed in.
    func mix(primary sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let primaryBuffer = AudioConversion.pcmBuffer(from: sampleBuffer, targetFormat: format) else {
            return sampleBuffer
        }
        let start = sampleBuffer.presentationTimeStamp
        let frameCount = Int(primaryBuffer.frameLength)
        let sampleRate = format.sampleRate
        let end = start + CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(sampleRate))

        lock.lock()
        let candidates = pending
        pending.removeAll { $0.pts + CMTime(value: CMTimeValue($0.buffer.frameLength),
                                            timescale: CMTimeScale(sampleRate)) <= start }
        lock.unlock()

        guard let primaryData = primaryBuffer.floatChannelData else { return sampleBuffer }
        let channels = Int(format.channelCount)

        for entry in candidates {
            guard let secondaryData = entry.buffer.floatChannelData else { continue }
            let secondaryStart = entry.pts
            let secondaryFrames = Int(entry.buffer.frameLength)
            let secondaryEnd = secondaryStart + CMTime(value: CMTimeValue(secondaryFrames),
                                                       timescale: CMTimeScale(sampleRate))
            guard secondaryEnd > start, secondaryStart < end else { continue }

            // Offset of the secondary buffer relative to the primary one.
            let offsetSeconds = (secondaryStart - start).seconds
            let offsetFrames = Int((offsetSeconds * sampleRate).rounded())

            for channel in 0..<channels {
                let destination = primaryData[channel]
                let sourceChannel = min(channel, Int(entry.buffer.format.channelCount) - 1)
                let source = secondaryData[sourceChannel]
                for frame in 0..<secondaryFrames {
                    let destinationIndex = frame + offsetFrames
                    guard destinationIndex >= 0, destinationIndex < frameCount else { continue }
                    let sum = destination[destinationIndex] + source[frame]
                    destination[destinationIndex] = max(-1, min(1, sum))
                }
            }
        }

        return AudioConversion.sampleBuffer(from: primaryBuffer, presentationTime: start)
    }

    func reset() {
        lock.lock()
        pending.removeAll()
        lock.unlock()
    }
}

/// CMSampleBuffer <-> AVAudioPCMBuffer plumbing.
enum AudioConversion {

    static func format(of sampleBuffer: CMSampleBuffer) -> AVAudioFormat? {
        guard let description = sampleBuffer.formatDescription,
              let streamDescription = description.audioStreamBasicDescription else { return nil }
        var asbd = streamDescription
        return AVAudioFormat(streamDescription: &asbd)
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer,
                          targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let sourceFormat = format(of: sampleBuffer) else { return nil }
        guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                            frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) else {
            return nil
        }
        source.frameLength = AVAudioFrameCount(sampleBuffer.numSamples)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(sampleBuffer.numSamples),
            into: source.mutableAudioBufferList)
        guard status == noErr else { return nil }

        if sourceFormat == targetFormat { return source }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let output = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                            frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples) + 1024) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, statusPointer in
            if consumed {
                statusPointer.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPointer.pointee = .haveData
            return source
        }
        return error == nil ? output : nil
    }

    static func sampleBuffer(from buffer: AVAudioPCMBuffer,
                             presentationTime: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMAudioFormatDescription?
        var asbd = buffer.format.streamDescription.pointee
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                             asbd: &asbd,
                                             layoutSize: 0,
                                             layout: nil,
                                             magicCookieSize: 0,
                                             magicCookie: nil,
                                             extensions: nil,
                                             formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid)

        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                   dataBuffer: nil,
                                   dataReady: false,
                                   makeDataReadyCallback: nil,
                                   refcon: nil,
                                   formatDescription: formatDescription,
                                   sampleCount: CMItemCount(buffer.frameLength),
                                   sampleTimingEntryCount: 1,
                                   sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0,
                                   sampleSizeArray: nil,
                                   sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer,
                                                             blockBufferAllocator: kCFAllocatorDefault,
                                                             blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                             flags: 0,
                                                             bufferList: buffer.audioBufferList) == noErr else {
            return nil
        }
        CMSampleBufferSetDataReady(sampleBuffer)
        return sampleBuffer
    }
}
