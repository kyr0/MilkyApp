import SwiftUI
import Combine
import Foundation
import os

/// Data structure for audio data
struct AudioData {
    var samplesData: [UInt8]
    var fftData: [UInt8]
    var sampleRate: Int
}

/// Double-buffered cache using `DispatchQueue` for minimal locking
final class DecoupledCache<T> {
    private var buffer1: T
    private var buffer2: T
    private var useBuffer1ForRead = true  // Tracks the current read buffer
    private let queue = DispatchQueue(label: "DecoupledCacheQueue", attributes: .concurrent)

    init(initialValue: T) {
        buffer1 = initialValue
        buffer2 = initialValue
    }

    /// Write data to the inactive buffer and toggle
    func write(_ writer: @escaping (inout T) -> Void) {
        queue.async(flags: .barrier) {
            // Select the inactive buffer for writing
            if self.useBuffer1ForRead {
                var tempBuffer = self.buffer2  // Create a temporary variable
                writer(&tempBuffer)  // Modify the temporary variable
                self.buffer2 = tempBuffer  // Assign the modified buffer back
            } else {
                var tempBuffer = self.buffer1
                writer(&tempBuffer)
                self.buffer1 = tempBuffer
            }
            self.useBuffer1ForRead.toggle()  // Toggle buffer
        }
    }

    /// Read data from the active buffer
    func read(_ reader: @escaping (T) -> Void) {
        queue.sync {
            let readBuffer = useBuffer1ForRead ? buffer1 : buffer2
            reader(readBuffer)
        }
    }
}

class SyncController: ObservableObject {
    @Published private(set) var isSyncing: Bool = false
    let sharedData = DecoupledCache<AudioData>(initialValue: AudioData(samplesData: [], fftData: [], sampleRate: 44_100))
    
    func startSyncing() {
        isSyncing = true
    }
    
    func stopSyncing() {
        isSyncing = false
    }
}

@MainActor
struct RecordingView: View {
    @StateObject var recorder: ProcessTapRecorder
    @State private var detachedWindow: DetachedWindow?
    @State private var lastRecordingURL: URL?
    @StateObject private var syncController = SyncController()
    
    @State private var width: Int = 720
    @State private var height: Int = 450
    @State private var oversamplingFactor: Int = 1
    @State private var showFPS: Bool = true
    @State private var fullscreenMode: Bool = false
    @State private var bitDepth: Int = 32
    @State private var targetFPS: Int = 30
    
    var body: some View {
        Form {
            Section(header: Text("Settings")) {
                HStack {
                    TextField("Width", value: $width, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .fixedSize(horizontal: false, vertical: false)
                }
                HStack {
                    TextField("Height", value: $height, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .fixedSize(horizontal: false, vertical: false)
                }
                HStack {
                    Picker("Oversampling", selection: $oversamplingFactor) {
                        Text("Off").tag(1)
                        Text("2x").tag(2)
                        Text("4x").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: false, vertical: false)
                }
                Toggle("Show FPS", isOn: $showFPS)
                    .fixedSize(horizontal: false, vertical: false)
                Toggle("Fullscreen", isOn: $fullscreenMode)
                    .fixedSize(horizontal: false, vertical: false)
                HStack {
                    Picker("Bit Depth", selection: $bitDepth) {
                        Text("32 bit").tag(32)
                        Text("24 bit").tag(24)
                        Text("16 bit").tag(16)
                        Text("8 bit").tag(8)
                    }
                    .pickerStyle(.segmented)
                }
                    .fixedSize(horizontal: false, vertical: false)
                HStack {
                    Picker("Target FPS", selection: $targetFPS) {
                        Text("24 (cinematic)").tag(24)
                        Text("30 (normal)").tag(30)
                    }
                }
                    .fixedSize(horizontal: false, vertical: false)
            }
           
        }
        
        Section {
            HStack {
                if recorder.isRecording {
                    Button("Stop") {
                        recorder.stop()
                        stopAudioSyncLoop()
                    }
                    .id("stop_button")
                } else {
                    Button("Start") {
                        handlingErrors {
                            try recorder.start()
                            startAudioSyncLoop()
                            closeMainWindow()
                            openDetachedWindow()
                        }
                    }
                    .id("start_button")
                    
                    if let lastRecordingURL {
                        FileProxyView(url: lastRecordingURL)
                            .transition(.scale.combined(with: .opacity))
                            .id("last_recording_view")
                    }
                }
            }
            .animation(.smooth, value: recorder.isRecording)
            .animation(.smooth, value: lastRecordingURL)
            .id("controls_section")
            .onChange(of: recorder.isRecording) { _, newValue in
                if !newValue { lastRecordingURL = recorder.fileURL }
            }
        }
    }
    
    func closeMainWindow() {
        NSApp.hide(nil)
    }
    
    func openDetachedWindow() {
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowX: Int = Int((screenFrame.width - CGFloat(width)) / 2)
            let windowY: Int = Int((screenFrame.height - CGFloat(height)) / 2)

            let detachedWindow = DetachedWindow(contentRect: NSRect(x: windowX, y: windowY, width: width, height: height))
            self.detachedWindow = detachedWindow
            
            if fullscreenMode {
                detachedWindow.toggleFullScreen(nil)
            }
        }
    }
    
    func startAudioSyncLoop() {
        syncController.startSyncing()

        let audioQueue = DispatchQueue(label: "AudioQueue", qos: .userInteractive, attributes: .concurrent)
        let renderQueue = DispatchQueue(label: "RenderQueue", qos: .userInteractive, attributes: .concurrent)

        // Audio Queue (Producer)
        audioQueue.async {
            Task {
                var lastFrameTime = Date()
                let nanosecondsPerSecond: UInt64 = 1_000_000_000
                let sleepDuration = nanosecondsPerSecond / UInt64(targetFPS)
                while await syncController.isSyncing {
                    let samplesData = await recorder.samplesData
                    let fftData = await recorder.fftData
                    
                    let sampleRate = Int(await recorder.currentFormat.sampleRate)
                    let currentTime = Date()
                    let deltaTime = currentTime.timeIntervalSince(lastFrameTime)
                    lastFrameTime = currentTime
                    print("Audio Provider FPS:", 1.0 / max(deltaTime, 0.0001))
                    
                    syncController.sharedData.write { buffer in
                        buffer.samplesData = samplesData
                        buffer.fftData = fftData
                        buffer.sampleRate = sampleRate
                    }

                    try? await Task.sleep(nanoseconds: sleepDuration)  // Run as fast as possible
                }
            }
        }

        // Render Queue (Consumer)
        renderQueue.async {
            Task {
                var lastFrameTime = Date()
                var lastWidth = 0
                var lastHeight = 0
                let nanosecondsPerSecond: UInt64 = 1_000_000_000
                let sleepDuration = nanosecondsPerSecond / UInt64(targetFPS)

                while await syncController.isSyncing {
                    let (capturedWidth, capturedHeight, capturedOversamplingFactor, capturedBitDepth, capturedShowFPS) = await (
                        width, height, oversamplingFactor, bitDepth, showFPS
                    )

                    let currentTime = Date()
                    let deltaTime = currentTime.timeIntervalSince(lastFrameTime)
                    lastFrameTime = currentTime
                    print("Rendering Call FPS:", 1.0 / max(deltaTime, 0.0001))

                    syncController.sharedData.read { buffer in
                        if let detachedWindow = detachedWindow {
                            DispatchQueue.main.async {
                                // Ensure resizing happens on the main thread
                                if lastWidth == 0 || lastHeight == 0 || lastHeight != capturedHeight || lastWidth != capturedWidth {
                                    detachedWindow.setContentSize(NSSize(width: capturedWidth, height: capturedHeight))
                                    lastWidth = capturedWidth
                                    lastHeight = capturedHeight
                                }

                                detachedWindow.detachedViewController.updateData(
                                    samplesData: buffer.samplesData,
                                    fftData: buffer.fftData,
                                    width: Int(capturedWidth * capturedOversamplingFactor),
                                    height: Int(capturedHeight * capturedOversamplingFactor),
                                    bitdepth: capturedBitDepth,
                                    showFPS: capturedShowFPS,
                                    sampleRate: buffer.sampleRate
                                )
                            }
                        }
                    }

                    try? await Task.sleep(nanoseconds: sleepDuration)  // Maintain target FPS
                }
            }
        }
    }

    
    func stopAudioSyncLoop() {
        syncController.stopSyncing()
    }
    
    private func handlingErrors(perform block: () throws -> Void) {
        do {
            try block()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
