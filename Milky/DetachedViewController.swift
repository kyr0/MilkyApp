import AppKit
import MetalKit

class DetachedViewController: NSViewController, NSWindowDelegate {
    var metalView: MTKView!
    var fpsLabel: NSTextField!
    
    /// Incoming data properties
    var samplesData: [UInt8] = []
    var fftData: [UInt8] = []

    // Double-buffering pixel buffers
    private var pixelBufferA: [UInt8] = []
    private var pixelBufferB: [UInt8] = []
    private var bufferLock = NSLock()
    
    private var frameCount = 0
    private var lastTime: CFTimeInterval = CACurrentMediaTime()
    var imageView: NSImageView!
    
    var width = 320
    var height = 200
    var lastFrameTime = Date()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize pixel buffers
        pixelBufferA = Array(repeating: 0, count: width * height * 4)
        pixelBufferB = Array(repeating: 0, count: width * height * 4)
        
        // Set up NSImageView to display the image
        imageView = NSImageView(frame: view.bounds)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        view.addSubview(imageView)

        // Set up FPS label
        fpsLabel = NSTextField(labelWithString: "FPS: 0")
        fpsLabel.frame = NSRect(x: 10, y: 10, width: 100, height: 20)
        fpsLabel.textColor = NSColor.white
        fpsLabel.font = NSFont.systemFont(ofSize: 14)
        fpsLabel.isEditable = false
        fpsLabel.isBezeled = false
        fpsLabel.drawsBackground = false
        view.addSubview(fpsLabel)
        
        // Start the continuous render loop in C
        pixelBufferA.withUnsafeMutableBytes { pixelBufferAPointer in
            pixelBufferB.withUnsafeMutableBytes { pixelBufferBPointer in
                let framePointerA = pixelBufferAPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let framePointerB = pixelBufferBPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                startContinuousRender(framePointerA, framePointerB, width, height, UInt8(32), 44100)
            }
        }

        // Timer to update the displayed image at approximately 60 FPS
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            self.updateImage()
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.delegate = self
    }
    
    func windowWillClose(_ notification: Notification) {
        // Terminate the app when the window closes
        NSApplication.shared.terminate(nil)
    }
    
    func updateData(samplesData: [UInt8], fftData: [UInt8], width: Int, height: Int, bitdepth: Int, showFPS: Bool, sampleRate: Int) {
        
        /*
        let currentTime = Date()
        let deltaTime = currentTime.timeIntervalSince(lastFrameTime)
        lastFrameTime = currentTime
        
        let clampedDeltaTime = max(deltaTime, 0.0001)
        let currentFPS = 1.0 / clampedDeltaTime
        
        // Update FPS label
        if showFPS {
            fpsLabel.stringValue = String(format: "FPS: %.2f", currentFPS)
        } else {
            fpsLabel.stringValue = ""
        }
        
        if samplesData.isEmpty || fftData.isEmpty {
            return
        }
        samplesData.withUnsafeBytes { samplesPointer in
            fftData.withUnsafeBytes { fftPointer in
                updateAudioData(samplesPointer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                fftPointer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                samplesData.count, fftData.count)
            }
        }
     */
    }
    
    func updateImage() {
        bufferLock.lock()
        
        // Get the display buffer with the most recently completed frame
        guard let currentBufferPointer = getDisplayBuffer() else {
            bufferLock.unlock()
            return
        }
        
        let currentTime = Date()
        let deltaTime = currentTime.timeIntervalSince(lastFrameTime)
        lastFrameTime = currentTime
        
        let clampedDeltaTime = max(deltaTime, 0.0001)
        let currentFPS = 1.0 / clampedDeltaTime
        
        // Update FPS label
        if true {
            fpsLabel.stringValue = String(format: "FPS: %.2f", currentFPS)
        } else {
            fpsLabel.stringValue = ""
        }
        
        
        // Convert the UnsafeMutablePointer to a [UInt8] array
        let bufferSize = width * height * 4 // Assuming 4 bytes per pixel (RGBA)
        let currentBuffer = Array(UnsafeBufferPointer(start: currentBufferPointer, count: bufferSize))
        
        // Create and update the NSImageView with the new image
        if let image = createImageFromRGBAData(samplesData: currentBuffer, width: width, height: height) {
            imageView.image = image
        }
        
        bufferLock.unlock()
    }
        
    private func createImageFromRGBAData(samplesData: [UInt8], width: Int, height: Int) -> NSImage? {
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(data: UnsafeMutableRawPointer(mutating: samplesData),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("Failed to create CGContext")
            return nil
        }

        guard let cgImage = context.makeImage() else {
            print("Failed to create CGImage from context")
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
