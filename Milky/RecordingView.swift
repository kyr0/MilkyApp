import SwiftUI
import Combine
import Foundation

/// Shared data structure
class SharedAudioData {
    private let queue = DispatchQueue(label: "AudioDataQueue", attributes: .concurrent)
    private var semaphore = DispatchSemaphore(value: 1)
    
    private var samplesData: [UInt8] = []
    private var fftData: [UInt8] = []
    private var sampleRate: Int = 44_100
    
    func update(samplesData: [UInt8], fftData: [UInt8], sampleRate: Int) {
        semaphore.wait()
        self.samplesData = samplesData
        self.fftData = fftData
        self.sampleRate = sampleRate
        semaphore.signal()
    }
    
    func read() -> (samplesData: [UInt8], fftData: [UInt8], sampleRate: Int) {
        semaphore.wait()
        let data = (samplesData, fftData, sampleRate)
        semaphore.signal()
        return data
    }
}

class SyncController: ObservableObject {
    @Published private(set) var isSyncing: Bool = false
    let sharedData = SharedAudioData()
    
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
        
        let audioQueue = DispatchQueue(label: "AudioQueue", qos: .userInitiated, attributes: .concurrent)
        let renderQueue = DispatchQueue(label: "RenderQueue", qos: .userInteractive, attributes: .concurrent)
        
        audioQueue.async {
            Task {
                while await syncController.isSyncing {
                    let samplesData = await recorder.samplesData
                    let fftData = await recorder.fftData
                    let sampleRate = Int(await recorder.currentFormat.sampleRate)
                    
                    await syncController.sharedData.update(samplesData: samplesData, fftData: fftData, sampleRate: sampleRate)
                    
                    try? await Task.sleep(nanoseconds: 5) /// as fast as possible
                }
            }
        }
        
        renderQueue.async {
            Task {
                var lastFrameTime = Date()
                var lastWidth = 0
                var lastHeight = 0
                let nanosecondsPerSecond: UInt64 = 1_000_000_000
                let sleepDuration = nanosecondsPerSecond / UInt64(await targetFPS)
                
                while await syncController.isSyncing {
                    let (capturedWidth, capturedHeight, capturedOversamplingFactor, capturedBitDepth, capturedShowFPS) = await (
                        width, height, oversamplingFactor, bitDepth, showFPS
                    )
                    
                    let currentTime = Date()
                    let deltaTime = currentTime.timeIntervalSince(lastFrameTime)
                    lastFrameTime = currentTime
                    print("Rendering FPS:", 1.0 / max(deltaTime, 0.0001))
                    
                    let (samplesData, fftData, sampleRate) = await syncController.sharedData.read()
                    
                    if let detachedWindow = await detachedWindow {
                        if lastWidth == 0 || lastHeight == 0 || lastHeight != capturedHeight || lastWidth != capturedWidth {
                            await detachedWindow.setContentSize(NSSize(width: capturedWidth, height: capturedHeight))
                            lastWidth = capturedWidth
                            lastHeight = capturedHeight
                        }
                        
                        await detachedWindow.detachedViewController.updateData(
                            samplesData: samplesData,
                            fftData: fftData,
                            width: Int(capturedWidth * capturedOversamplingFactor),
                            height: Int(capturedHeight * capturedOversamplingFactor),
                            bitdepth: capturedBitDepth,
                            showFPS: capturedShowFPS,
                            sampleRate: sampleRate
                        )
                    }
                    
                    try? await Task.sleep(nanoseconds: sleepDuration) /// desired FPS, set by user; tested: works (up to 9000 FPS (!!)  if no audio stream "attached")
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
