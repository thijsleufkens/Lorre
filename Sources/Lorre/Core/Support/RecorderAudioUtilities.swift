#if canImport(AVFoundation)
@preconcurrency import AVFoundation
import CoreMedia
import Foundation

enum RecorderAudioUtilities {
    private final class ConversionInputState: @unchecked Sendable {
        private let lock = NSLock()
        private var hasSuppliedInput = false

        func nextBuffer(
            from buffer: AVAudioPCMBuffer,
            outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>
        ) -> AVAudioBuffer? {
            lock.lock()
            defer { lock.unlock() }

            guard hasSuppliedInput == false else {
                outStatus.pointee = .endOfStream
                return nil
            }

            hasSuppliedInput = true
            outStatus.pointee = .haveData
            return buffer
        }
    }

    static let previewFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    }()

    static func extractPCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw LorreError.recordingStartFailed("System audio stream format is unavailable.")
        }

        var sourceStreamDescription = streamDescription.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &sourceStreamDescription) else {
            throw LorreError.recordingStartFailed("System audio format is unsupported.")
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw LorreError.recordingStartFailed("Could not allocate system audio buffer.")
        }
        buffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw LorreError.recordingStartFailed("Could not copy system audio samples (status: \(status)).")
        }
        return buffer
    }

    static func convert(_ buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == outputFormat {
            guard let copy = buffer.lorre_deepCopy() else {
                throw LorreError.recordingStartFailed("Could not copy audio buffer.")
            }
            return copy
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            throw LorreError.recordingStartFailed("Could not prepare audio format converter.")
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let estimatedCapacity = max(1, Int(ceil(Double(buffer.frameLength) * ratio)) + 32)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(estimatedCapacity)
        ) else {
            throw LorreError.recordingStartFailed("Could not allocate converted audio buffer.")
        }

        let inputState = ConversionInputState()
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            inputState.nextBuffer(from: buffer, outStatus: outStatus)
        }

        if let conversionError {
            throw LorreError.recordingStartFailed(conversionError.localizedDescription)
        }

        guard status == .haveData || status == .inputRanDry || status == .endOfStream else {
            throw LorreError.recordingStartFailed("Audio conversion failed.")
        }
        return outputBuffer
    }

    static func makePCMBuffer(from samples: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard format.commonFormat == .pcmFormatFloat32,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ) else {
            throw LorreError.recordingStartFailed("Could not allocate mixed audio buffer.")
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.floatChannelData else {
            throw LorreError.recordingStartFailed("Mixed audio buffer has no channel data.")
        }

        let channelCount = Int(format.channelCount)
        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            for channel in 0..<channelCount {
                channelData[channel].update(from: baseAddress, count: samples.count)
            }
        }
        return buffer
    }

    static func write(samples: [Float], to url: URL, format: AVAudioFormat) throws {
        let buffer = try makePCMBuffer(from: samples, format: format)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    /// Mixes the microphone and system stems into the canonical mono file.
    /// Streams both inputs chunk-wise in two passes (peak scan, then scaled
    /// write) so multi-hour recordings never need whole stems in memory.
    static func mixToCanonicalFile(
        microphoneURL: URL,
        systemAudioURL: URL,
        destinationURL: URL,
        targetFormat: AVAudioFormat = RecorderAudioUtilities.previewFormat
    ) throws {
        // Pass 1: global peak, so normalization scales the whole mix uniformly.
        var peak: Float = 0
        var totalFrames = 0
        try streamMixedChunks(
            microphoneURL: microphoneURL,
            systemAudioURL: systemAudioURL,
            targetFormat: targetFormat
        ) { chunk in
            totalFrames += chunk.count
            for value in chunk {
                peak = max(peak, abs(value))
            }
        }

        guard totalFrames > 0 else {
            try write(samples: [], to: destinationURL, format: targetFormat)
            return
        }
        let gain: Float = peak > 0.98 ? 0.98 / peak : 1

        // Pass 2: write scaled chunks.
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        let outputFile = try AVAudioFile(forWriting: destinationURL, settings: targetFormat.settings)
        try streamMixedChunks(
            microphoneURL: microphoneURL,
            systemAudioURL: systemAudioURL,
            targetFormat: targetFormat
        ) { chunk in
            let scaled = gain == 1 ? chunk : chunk.map { $0 * gain }
            let buffer = try makePCMBuffer(from: scaled, format: targetFormat)
            try outputFile.write(from: buffer)
        }
    }

    private static let mixChunkFrames: AVAudioFrameCount = 65_536

    private static func streamMixedChunks(
        microphoneURL: URL,
        systemAudioURL: URL,
        targetFormat: AVAudioFormat,
        process: ([Float]) throws -> Void
    ) throws {
        let microphoneReader = try ChunkedSampleReader(url: microphoneURL, targetFormat: targetFormat)
        let systemReader = try ChunkedSampleReader(url: systemAudioURL, targetFormat: targetFormat)
        let voiceGain: Float = 0.70710677
        let systemGain: Float = 0.70710677
        let headroom: Float = 0.8

        while true {
            let microphone = try microphoneReader.next(maxFrames: mixChunkFrames)
            let system = try systemReader.next(maxFrames: mixChunkFrames)
            if microphone.isEmpty, system.isEmpty { break }

            let count = max(microphone.count, system.count)
            var mixed = [Float](repeating: 0, count: count)
            for index in 0..<count {
                let microphoneSample = index < microphone.count ? microphone[index] : 0
                let systemSample = index < system.count ? system[index] : 0
                mixed[index] = ((microphoneSample * voiceGain) + (systemSample * systemGain)) * headroom
            }
            try process(mixed)
        }
    }

    /// Reads an audio file in fixed-size chunks, converting to `targetFormat`
    /// with a persistent converter so resampling state carries across chunks
    /// and the resampler tail is drained at end-of-stream (the one-shot
    /// `convert(_:to:)` path truncates the tail of long rate conversions).
    /// `next(maxFrames:)` returns exactly `maxFrames` samples until the file
    /// runs out, which keeps two parallel readers sample-aligned.
    private final class ChunkedSampleReader {
        private let file: AVAudioFile
        private let targetFormat: AVAudioFormat
        private let converter: AVAudioConverter?
        private var sourceExhausted = false
        private var converterDrained = false

        /// Format of the buffers fed into the converter. Differs from the
        /// file's format for >2-channel sources: AVAudioConverter silently
        /// produces all-zero output when downmixing more than two channels
        /// to mono (seen with the 5-channel input macOS voice processing
        /// reports for the built-in mic), so those are reduced to channel 0
        /// manually before conversion.
        private let supplyFormat: AVAudioFormat
        private let reducesToMono: Bool

        init(url: URL, targetFormat: AVAudioFormat) throws {
            self.file = try AVAudioFile(forReading: url)
            self.targetFormat = targetFormat
            let sourceFormat = file.processingFormat
            if sourceFormat.channelCount > 2 {
                guard let mono = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: sourceFormat.sampleRate,
                    channels: 1,
                    interleaved: false
                ) else {
                    throw LorreError.recordingStopFailed("Could not prepare audio format converter.")
                }
                self.supplyFormat = mono
                self.reducesToMono = true
            } else {
                self.supplyFormat = sourceFormat
                self.reducesToMono = false
            }
            if supplyFormat == targetFormat {
                self.converter = nil
            } else {
                guard let converter = AVAudioConverter(from: supplyFormat, to: targetFormat) else {
                    throw LorreError.recordingStopFailed("Could not prepare audio format converter.")
                }
                self.converter = converter
            }
        }

        private func monoReduced(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            guard reducesToMono else { return buffer }
            guard let source = buffer.floatChannelData,
                  let mono = AVAudioPCMBuffer(pcmFormat: supplyFormat, frameCapacity: buffer.frameLength) else {
                return nil
            }
            mono.frameLength = buffer.frameLength
            mono.floatChannelData?[0].update(from: source[0], count: Int(buffer.frameLength))
            return mono
        }

        func next(maxFrames: AVAudioFrameCount) throws -> [Float] {
            var collected: [Float] = []
            collected.reserveCapacity(Int(maxFrames))
            while collected.count < Int(maxFrames) {
                let produced = try produceSome(upTo: AVAudioFrameCount(Int(maxFrames) - collected.count))
                if produced.isEmpty { break }
                collected.append(contentsOf: produced)
            }
            return collected
        }

        private func produceSome(upTo frames: AVAudioFrameCount) throws -> [Float] {
            guard let converter else {
                return try readDirectly(upTo: frames)
            }
            if converterDrained { return [] }

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frames) else {
                throw LorreError.recordingStopFailed("Could not allocate converted audio buffer.")
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { [self] requested, outStatus in
                if sourceExhausted {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                let framesToRead = min(requested, RecorderAudioUtilities.mixChunkFrames)
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: framesToRead
                ) else {
                    sourceExhausted = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inputBuffer, frameCount: framesToRead)
                } catch {
                    sourceExhausted = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard inputBuffer.frameLength > 0, let supplied = monoReduced(inputBuffer) else {
                    sourceExhausted = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return supplied
            }

            if let conversionError {
                throw LorreError.recordingStopFailed(conversionError.localizedDescription)
            }
            if status == .error {
                throw LorreError.recordingStopFailed("Audio conversion failed.")
            }

            guard outputBuffer.frameLength > 0 else {
                if status == .endOfStream || sourceExhausted {
                    converterDrained = true
                }
                return []
            }
            return Self.monoSamples(from: outputBuffer)
        }

        private func readDirectly(upTo frames: AVAudioFrameCount) throws -> [Float] {
            let remaining = file.length - file.framePosition
            guard remaining > 0 else { return [] }
            let framesToRead = AVAudioFrameCount(min(Int64(frames), remaining))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: framesToRead) else {
                throw LorreError.recordingStopFailed("Could not load recorded audio for mixing.")
            }
            try file.read(into: buffer, frameCount: framesToRead)
            guard buffer.frameLength > 0 else { return [] }
            return Self.monoSamples(from: buffer)
        }

        private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
            guard let channelData = buffer.floatChannelData else { return [] }
            return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        }
    }
}

extension AVAudioPCMBuffer {
    /// Reduces a multichannel float buffer to a mono buffer holding channel 0.
    /// Used for the >2-channel input macOS voice processing reports for the
    /// built-in mic — AVAudioConverter silently zeroes such input when asked
    /// to downmix, so channel selection has to happen before any conversion.
    /// Returns `self` when the buffer is already mono.
    func lorre_monoChannelZero() -> AVAudioPCMBuffer? {
        guard format.channelCount > 1 else { return self }
        guard format.commonFormat == .pcmFormatFloat32, let source = floatChannelData else { return nil }
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        ), let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameLength) else {
            return nil
        }
        mono.frameLength = frameLength
        guard let destination = mono.floatChannelData else { return nil }
        if format.isInterleaved {
            let stride = Int(format.channelCount)
            for frame in 0..<Int(frameLength) {
                destination[0][frame] = source[0][frame * stride]
            }
        } else {
            destination[0].update(from: source[0], count: Int(frameLength))
        }
        return mono
    }

    func lorre_deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        copy.frameLength = frameLength

        let frameCount = Int(frameLength)
        let channelCount = Int(format.channelCount)
        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let source = floatChannelData, let destination = copy.floatChannelData else { return nil }
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return copy
        case .pcmFormatInt16:
            guard let source = int16ChannelData, let destination = copy.int16ChannelData else { return nil }
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return copy
        case .pcmFormatInt32:
            guard let source = int32ChannelData, let destination = copy.int32ChannelData else { return nil }
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return copy
        default:
            return nil
        }
    }

    func lorre_meterLevel() -> Double {
        let frameCount = Int(frameLength)
        guard frameCount > 0 else { return 0.05 }

        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else { return 0.05 }

        var peak: Double = 0
        var sumSquares: Double = 0
        var sampleCount = 0

        switch format.commonFormat {
        case .pcmFormatFloat32:
            if let channels = floatChannelData {
                for channel in 0..<channelCount {
                    let values = UnsafeBufferPointer(start: channels[channel], count: frameCount)
                    for sample in values {
                        let value = Double(abs(sample))
                        peak = max(peak, value)
                        sumSquares += value * value
                        sampleCount += 1
                    }
                }
            } else {
                let audioBuffers = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
                guard let first = audioBuffers.first, let data = first.mData else { return 0.05 }
                let samples = data.assumingMemoryBound(to: Float.self)
                let total = frameCount * channelCount
                for index in 0..<total {
                    let value = Double(abs(samples[index]))
                    peak = max(peak, value)
                    sumSquares += value * value
                }
                sampleCount = total
            }
        case .pcmFormatInt16:
            if let channels = int16ChannelData {
                for channel in 0..<channelCount {
                    let values = UnsafeBufferPointer(start: channels[channel], count: frameCount)
                    for sample in values {
                        let normalized = Double(Swift.abs(Int32(sample))) / Double(Int16.max)
                        peak = max(peak, normalized)
                        sumSquares += normalized * normalized
                        sampleCount += 1
                    }
                }
            } else {
                let audioBuffers = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
                guard let first = audioBuffers.first, let data = first.mData else { return 0.05 }
                let samples = data.assumingMemoryBound(to: Int16.self)
                let total = frameCount * channelCount
                for index in 0..<total {
                    let normalized = Double(Swift.abs(Int32(samples[index]))) / Double(Int16.max)
                    peak = max(peak, normalized)
                    sumSquares += normalized * normalized
                }
                sampleCount = total
            }
        case .pcmFormatInt32:
            if let channels = int32ChannelData {
                for channel in 0..<channelCount {
                    let values = UnsafeBufferPointer(start: channels[channel], count: frameCount)
                    for sample in values {
                        let normalized = Double(Swift.abs(Int64(sample))) / Double(Int32.max)
                        peak = max(peak, normalized)
                        sumSquares += normalized * normalized
                        sampleCount += 1
                    }
                }
            } else {
                let audioBuffers = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
                guard let first = audioBuffers.first, let data = first.mData else { return 0.05 }
                let samples = data.assumingMemoryBound(to: Int32.self)
                let total = frameCount * channelCount
                for index in 0..<total {
                    let normalized = Double(Swift.abs(Int64(samples[index]))) / Double(Int32.max)
                    peak = max(peak, normalized)
                    sumSquares += normalized * normalized
                }
                sampleCount = total
            }
        default:
            return 0.05
        }

        guard sampleCount > 0 else { return 0.05 }
        let rms = sqrt(sumSquares / Double(sampleCount))
        let rmsDb = 20.0 * log10(max(rms, 0.000_1))
        let peakDb = 20.0 * log10(max(peak, 0.000_1))
        let rmsNormalized = max(0.0, min(1.0, (rmsDb + 58.0) / 38.0))
        let peakNormalized = max(0.0, min(1.0, (peakDb + 46.0) / 34.0))
        let blended = max(rmsNormalized * 0.92, peakNormalized * 0.88)
        let gated = max(0.0, blended - 0.02) / 0.98
        let gained = min(1.0, gated * 1.45)
        return max(0.02, pow(gained, 0.68))
    }
}
#endif
