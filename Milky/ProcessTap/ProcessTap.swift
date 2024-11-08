import SwiftUI
import AudioToolbox
import OSLog
import Accelerate
import AVFoundation
import Accelerate
import Combine

/// pre-create FFT setups for different buffer sizes
let fftSetups: [Int: FFTSetup] = {
    let sizes = [128, 256, 512, 1024, 2048]
    var setups = [Int: FFTSetup]()
    for size in sizes {
        let log2n = vDSP_Length(log2(Double(size)))
        if let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) {
            setups[size] = setup
        } else {
            print("Failed to create FFT setup for size \(size)")
        }
    }
    return setups
}()

/// pre-allocated memory buffers for FFT processing
let preallocatedBuffers: [Int: (realp: UnsafeMutablePointer<Float>, imagp: UnsafeMutablePointer<Float>)] = {
    var buffers = [Int: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>)]()
    for size in fftSetups.keys {
        buffers[size] = (
            UnsafeMutablePointer<Float>.allocate(capacity: size / 2),
            UnsafeMutablePointer<Float>.allocate(capacity: size / 2)
        )
    }
    return buffers
}()

/// perform FFT with preconfigured setups based on buffer size
func performFFT(on buffer: AVAudioPCMBuffer, sampleRate: Double) -> [Float] {
    let frameLength = Int(buffer.frameLength)
    let fftSize = fftSetups.keys.filter { $0 <= frameLength }.max() ?? 2048

    guard let fftSetup = fftSetups[fftSize],
          let (realp, imagp) = preallocatedBuffers[fftSize] else {
        print("FFT setup or buffers not found for size \(fftSize)")
        return []
    }

    /// truncate or pad the frame length to match the selected FFT size
    let sampleCount = min(frameLength, fftSize)
    let channelData = buffer.floatChannelData![0]
    let samples = Array(UnsafeBufferPointer(start: channelData, count: sampleCount))

    /// prepare complex buffer for FFT
    var complexBuffer = DSPSplitComplex(realp: realp, imagp: imagp)
    samples.withUnsafeBufferPointer { samplesPointer in
        samplesPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: sampleCount) { complexPointer in
            vDSP_ctoz(complexPointer, 2, &complexBuffer, 1, vDSP_Length(sampleCount / 2))
        }
    }

    /// perform actual FFT
    vDSP_fft_zrip(fftSetup, &complexBuffer, 1, vDSP_Length(log2(Double(fftSize))), FFTDirection(FFT_FORWARD))

    /// calculate magnitudes
    var magnitudes = [Float](repeating: 0.0, count: sampleCount / 2)
    vDSP_zvmags(&complexBuffer, 1, &magnitudes, 1, vDSP_Length(sampleCount / 2))

    /// take square root to get amplitude spectrum
    var sqrtMagnitudes = [Float](repeating: 0.0, count: sampleCount / 2)
    vvsqrtf(&sqrtMagnitudes, magnitudes, [Int32(sampleCount / 2)])

    /// normalize the magnitudes
    var normalizedMagnitudes = [Float](repeating: 0.0, count: sampleCount / 2)
    var scale: Float = 2.0 / Float(fftSize)
    vDSP_vsmul(&sqrtMagnitudes, 1, &scale, &normalizedMagnitudes, 1, vDSP_Length(sampleCount / 2))

    return normalizedMagnitudes
}


@Observable
final class ProcessTap {

    typealias InvalidationHandler = (ProcessTap) -> Void

    let process: AudioProcess
    let muteWhenRunning: Bool
    private let logger: Logger

    private(set) var errorMessage: String? = nil

    init(process: AudioProcess, muteWhenRunning: Bool = false) {
        self.process = process
        self.muteWhenRunning = muteWhenRunning
        self.logger = Logger(subsystem: kAppSubsystem, category: "\(String(describing: ProcessTap.self))(\(process.name))")
    }

    @ObservationIgnored
    private var processTapID: AudioObjectID = .unknown
    @ObservationIgnored
    private var aggregateDeviceID = AudioObjectID.unknown
    @ObservationIgnored
    private var deviceProcID: AudioDeviceIOProcID?
    @ObservationIgnored
    private(set) var tapStreamDescription: AudioStreamBasicDescription?
    @ObservationIgnored
    private var invalidationHandler: InvalidationHandler?

    @ObservationIgnored
    private(set) var activated = false

    @MainActor
    func activate() {
        guard !activated else { return }
        activated = true

        logger.debug(#function)

        self.errorMessage = nil

        do {
            try prepare(for: process.objectID)
        } catch {
            logger.error("\(error, privacy: .public)")
            self.errorMessage = error.localizedDescription
        }
    }

    func invalidate() {
        guard activated else { return }
        defer { activated = false }

        logger.debug(#function)

        invalidationHandler?(self)
        self.invalidationHandler = nil

        if aggregateDeviceID.isValid {
            var err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr { logger.warning("Failed to stop aggregate device: \(err, privacy: .public)") }

            if let deviceProcID {
                err = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                if err != noErr { logger.warning("Failed to destroy device I/O proc: \(err, privacy: .public)") }
                self.deviceProcID = nil
            }

            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                logger.warning("Failed to destroy aggregate device: \(err, privacy: .public)")
            }
            aggregateDeviceID = .unknown
        }

        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err != noErr {
                logger.warning("Failed to destroy audio tap: \(err, privacy: .public)")
            }
            self.processTapID = .unknown
        }
    }
    
    func cleanup() {
        if activated {
            logger.debug("Cleaning up ProcessTap")
            invalidate()  // Invalidate to disconnect and release resources
        }
    }

    private func prepare(for objectID: AudioObjectID) throws {
        errorMessage = nil

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [objectID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = muteWhenRunning ? .mutedWhenTapped : .unmuted
        var tapID: AUAudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard err == noErr else {
            errorMessage = "Process tap creation failed with error \(err)"
            return
        }

        logger.debug("Created process tap #\(tapID, privacy: .public)")

        self.processTapID = tapID

        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()

        let outputUID = try systemOutputID.readDeviceUID()

        let aggregateUID = UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MilkyTap-\(process.id)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()

        aggregateDeviceID = AudioObjectID.unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            throw "Failed to create aggregate device: \(err)"
        }

        logger.debug("Created aggregate device #\(self.aggregateDeviceID, privacy: .public)")
        
        // Call the C function with the pointer to `deviceProcID`
        StartAudioCapture(aggregateDeviceID, &deviceProcID)

    }

    func run(on queue: DispatchQueue, ioBlock: @escaping AudioDeviceIOBlock, invalidationHandler: @escaping InvalidationHandler) throws {
        assert(activated, "\(#function) called with inactive tap!")
        assert(self.invalidationHandler == nil, "\(#function) called with tap already active!")

        errorMessage = nil

        logger.debug("Run tap!")

        self.invalidationHandler = invalidationHandler

        var err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
        guard err == noErr else { throw "Failed to create device I/O proc: \(err)" }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else { throw "Failed to start audio device: \(err)" }
    }

    deinit { invalidate() }

}

let visualizationFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100.0, channels: 1, interleaved: false)!

@Observable
@MainActor
final class ProcessTapRecorder: ObservableObject {

    let fileURL: URL
    let process: AudioProcess
    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInteractive, attributes: .concurrent)
    private let logger: Logger
    
    var currentFormat: AVAudioFormat
    var fftData: [UInt8] = []
    var samplesData: [UInt8] = []
    private var updateCounter = 0
    
    func stopAllTapsAndCleanup() {
        logger.debug("Stopping all taps and performing cleanup")

        // Stop the recording if it's active
        if isRecording {
            stop()
        }

        // Ensure the tap is invalidated and cleaned up
        do {
            try tap.cleanup()
        } catch {
            logger.error("Failed to cleanup ProcessTap: \(error, privacy: .public)")
        }

        // Additional cleanup if needed
        _tap = nil  // Release the reference to the tap
    }
    
    private func updateSamplesAndFFT(buffer: AVAudioPCMBuffer) {
        updateCounter += 1
        
        let samples = processSamples(from: buffer)
        DispatchQueue.main.async {
            self.samplesData = samples
        }
        
        guard updateCounter % 2 == 0 else { return } /// throttle updates to every other frame
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let frequencyBins = self.performAndProcessFFT(on: buffer)
            
            DispatchQueue.main.async {
                self.fftData = frequencyBins
            }
        }
    }
    
    private func performAndProcessFFT(on buffer: AVAudioPCMBuffer) -> [UInt8] {
        let fftResult: [Float] = performFFT(on: buffer, sampleRate: buffer.format.sampleRate)
        var frequencyBins: [UInt8] = Array(repeating: 0, count: fftResult.count)
        
        for bin in 0..<fftResult.count {
            let fftValue = fftResult[bin]
            let scaledValue = fftValue * 127.5 + 128
            let clampedValue = max(0, min(255, Int(scaledValue)))
            frequencyBins[bin] = UInt8(clampedValue)
        }
        return frequencyBins
    }
    
    @ObservationIgnored
    private weak var _tap: ProcessTap?

    private(set) var isRecording = false

    init(fileURL: URL, tap: ProcessTap?) {
        self.process = tap!.process
        self.fileURL = fileURL
        self._tap = tap
        self.currentFormat = AVAudioFormat()
        self.logger = Logger(subsystem: kAppSubsystem, category: "\(String(describing: ProcessTapRecorder.self))(\(fileURL.lastPathComponent))")
    }

    private var tap: ProcessTap {
        get throws {
            guard let _tap else { throw "Process tab unavailable" }
            return _tap
        }
    }

    @ObservationIgnored
    private var currentFile: AVAudioFile?

    @MainActor
    func start() throws {
        logger.debug(#function)
        
        guard !isRecording else {
            logger.warning("\(#function, privacy: .public) while already recording")
            return
        }

        let tap = try tap

        if !tap.activated { tap.activate() }

        guard var streamDescription = tap.tapStreamDescription else {
            throw "Tap stream description not available."
        }

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw "Failed to create AVAudioFormat."
        }
        
        self.currentFormat = format

        logger.info("Using audio format: \(format, privacy: .public)")

        let settings: [String: Any] = [
            AVFormatIDKey: streamDescription.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount
        ]
        let file = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)

        self.currentFile = file

        try tap.run(on: queue) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self, let currentFile = self.currentFile else { return }
            do {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                    throw "Failed to create PCM buffer"
                }
                updateSamplesAndFFT(buffer: buffer)
                try currentFile.write(from: buffer)
            } catch {
                logger.error("\(error, privacy: .public)")
            }
        } invalidationHandler: { [weak self] tap in
            guard let self else { return }
            handleInvalidation()
        }

        isRecording = true
    }
    
    /// need to convert the CoreAudio buffer down to UInt8 array and downmix to mono if necessary
    private func processSamples(from buffer: AVAudioPCMBuffer) -> [UInt8] {
        var samples: [UInt8] = Array(repeating: 0, count: Int(buffer.frameLength))
        let leftChannel = buffer.floatChannelData![0]
        
        if buffer.format.channelCount > 1 {
            let rightChannel = buffer.floatChannelData![1]
            for frame in 0..<Int(buffer.frameLength) {
                let leftValue = leftChannel[frame]
                let rightValue = rightChannel[frame]
                let averageValue = (leftValue + rightValue) / 2.0
                let scaledValue = averageValue * 127.5 + 128
                let clampedValue = max(0, min(255, Int(scaledValue)))
                samples[frame] = UInt8(clampedValue)
            }
        } else {
            for frame in 0..<Int(buffer.frameLength) {
                let channelValue = leftChannel[frame]
                let scaledValue = channelValue * 127.5 + 128
                let clampedValue = max(0, min(255, Int(scaledValue)))
                samples[frame] = UInt8(clampedValue)
            }
        }
        return samples
    }

    func stop() {
        do {
            logger.debug(#function)
            guard isRecording else { return }
            currentFile = nil
            isRecording = false
            try tap.invalidate()
        } catch {
            logger.error("Stop failed: \(error, privacy: .public)")
        }
    }

    private func handleInvalidation() {
        guard isRecording else { return }
        logger.debug(#function)
    }

}
