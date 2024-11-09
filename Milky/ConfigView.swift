import SwiftUI
import Combine
import Foundation
import os

struct VisualizationConfig {
    var width: Int = 720
    var height: Int = 450
    var oversamplingFactor: Int = 1
    var showFPS: Bool = true
    var fullscreenMode: Bool = false
    var bitDepth: Int = 32
    var targetFPS: Int = 30
    var isVisualizing: Bool = false
}

@MainActor
struct ConfigView: View {
    
    let appIcon: NSImage
    let isRecording: Bool
    
    @State private var detachedWindow: DetachedWindow?
    @State private var width: Int = 720
    @State private var height: Int = 450
    @State private var oversamplingFactor: Int = 1
    @State private var showFPS: Bool = true
    @State private var fullscreenMode: Bool = false
    @State private var bitDepth: Int = 32
    @State private var targetFPS: Int = 30
    @State private var isVisualizing: Bool = false
    
    var body: some View {
        Form {
            Section {
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
                Toggle("Show FPS", isOn: $showFPS)
                    .fixedSize(horizontal: false, vertical: false)
                Toggle("Fullscreen", isOn: $fullscreenMode)
                    .fixedSize(horizontal: false, vertical: false)
            }.disabled(isVisualizing)
           
        }
        
        Section {
            HStack {
                if isVisualizing {
                    RecordingIndicator(appIcon: appIcon, isRecording: isRecording)
                    Text("Visualizing...")
                } else {
                    Button("Start") {
                        handlingErrors {
                            isVisualizing = true
                            openDetachedWindow()
                        }
                    }
                }
            }
        }
    }
    
    func openDetachedWindow() {
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowX: Int = Int((screenFrame.width - CGFloat(width)) / 2)
            let windowY: Int = Int((screenFrame.height - CGFloat(height)) / 2)

            let detachedWindow = DetachedWindow(contentRect: NSRect(x: windowX, y: windowY, width: width, height: height))
            self.detachedWindow = detachedWindow
            
            // Now we can use the auto-generated initializer
            let config = VisualizationConfig(
                width: width,
                height: height,
                oversamplingFactor: oversamplingFactor,
                showFPS: showFPS,
                fullscreenMode: fullscreenMode,
                bitDepth: bitDepth,
                targetFPS: targetFPS,
                isVisualizing: isVisualizing
            )
            
            detachedWindow.detachedViewController.setVisualizationConfig(config: config)
            
            detachedWindow.setFrame(NSRect(x: windowX, y: windowY, width: width, height: height), display: true)
            
            if fullscreenMode {
                detachedWindow.toggleFullScreen(nil)
            }
        }
    }
    
    private func handlingErrors(perform block: () throws -> Void) {
        do {
            try block()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
