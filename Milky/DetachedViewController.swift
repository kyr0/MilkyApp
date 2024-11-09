import AppKit
import MetalKit

struct RenderSize {
    var width: Int;
    var height: Int;
}

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
    private var lastFpsLogTime: TimeInterval = 0
    
    var config: VisualizationConfig?
    var renderSize: RenderSize = RenderSize(width: 320, height: 200)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up NSImageView to display the image
        imageView = NSImageView(frame: view.bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
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
        
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.delegate = self
    }
    
    func windowWillClose(_ notification: Notification) {
        // Terminate the app when the window closes
        NSApplication.shared.terminate(nil)
    }
    
    func setVisualizationConfig(config: VisualizationConfig) {
        self.config = config
        determineRenderSize()
        
        let bufferSize = renderSize.width * renderSize.height * 4
        let sleepTime =  Int(1.0 / Double(config.targetFPS) * 1000 * 1000)
        let desiredFPS = Int(config.targetFPS)
        
        // Initialize pixel buffers
        pixelBufferA = Array(repeating: 0, count: bufferSize)
        pixelBufferB = Array(repeating: 0, count: bufferSize)
        
        // Start the continuous render loop in C
        pixelBufferA.withUnsafeMutableBytes { pixelBufferAPointer in
            pixelBufferB.withUnsafeMutableBytes { pixelBufferBPointer in
                let framePointerA = pixelBufferAPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let framePointerB = pixelBufferBPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                startContinuousRender(
                    framePointerA,
                    framePointerB,
                    renderSize.width,
                    renderSize.height,
                    UInt8(config.bitDepth),
                    44100,
                    sleepTime,
                    desiredFPS
                )
            }
        }

        // Timer to update the displayed image at approximately 60 FPS
        Timer.scheduledTimer(withTimeInterval: 1.0 / Double(config.targetFPS), repeats: true) { _ in
            self.renderOnCanvas()
        }
    }
    
    func determineRenderSize() {
        if (config != nil) {
            if let _config = config {
                self.renderSize = RenderSize(
                    width: _config.width * _config.oversamplingFactor,
                    height: _config.height * _config.oversamplingFactor
                )
            }
        }
    }
    
    func renderOnCanvas() {
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
        if (config?.showFPS == true) {
            if currentTime.timeIntervalSinceReferenceDate - lastFpsLogTime >= 1.0 {
                fpsLabel.stringValue = String(format: "Paint FPS: %d", Int(currentFPS))
                lastFpsLogTime = currentTime.timeIntervalSinceReferenceDate
            }
        } else {
            fpsLabel.stringValue = ""
        }
        
        // Convert the UnsafeMutablePointer to a [UInt8] array
        let bufferSize = renderSize.width * renderSize.height * 4 // Assuming 4 bytes per pixel (RGBA)
        let currentBuffer = Array(UnsafeBufferPointer(start: currentBufferPointer, count: bufferSize))
        
        // Create and update the NSImageView with the new image
        if let image = createImageFromRGBAData(samplesData: currentBuffer, width: renderSize.width, height: renderSize.height) {
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
        
        context.interpolationQuality = .none

        guard let cgImage = context.makeImage() else {
            print("Failed to create CGImage from context")
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
