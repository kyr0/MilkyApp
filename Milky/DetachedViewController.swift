import AppKit
import MetalKit

class DetachedViewController: NSViewController, NSWindowDelegate {
    var metalView: MTKView!
    var fpsLabel: NSTextField!
    
    /// incoming data properties
    var samplesData: [UInt8] = []
    var fftData: [UInt8] = []

    private var frameCount = 0
    private var lastTime: CFTimeInterval = CACurrentMediaTime()
    var imageView: NSImageView!
    
    var width = 320
    var height = 200
    var pixelBuffer: [UInt8] = Array(repeating: 0, count: 256_000)
    var lastFrameTime = Date()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        /// Set up NSImageView to display the image
        imageView = NSImageView(frame: view.bounds)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        view.addSubview(imageView)

        /// Set up FPS label
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
        NSApplication.shared.terminate(nil) /// Terminate the app when the window closes
    }
     
    func updateData(samplesData: [UInt8], fftData: [UInt8], width: Int, height: Int, bitdepth: Int, showFPS: Bool, sampleRate: Int) {
        
        let currentTime = Date()
        let deltaTime = currentTime.timeIntervalSince(lastFrameTime)
        lastFrameTime = currentTime
        
        let clampedDeltaTime = max(deltaTime, 0.0001)
        let currentFPS = 1.0 / clampedDeltaTime
        
        if (showFPS == true) {
            fpsLabel.stringValue = String(format: "FPS: %.2f", currentFPS)
        } else {
            fpsLabel.stringValue = String("")
        }
        
        /// make local copies to avoid overlapping access issues
        var localSamplesData = Data(samplesData)
        var localFFTData = Data(fftData)
        let localSamplesDataCount = samplesData.count
        let localFFTDataCount = fftData.count
        let currentTimeCASecs = size_t(CACurrentMediaTime() * 1000);
        let renderBitdepth = UInt8(bitdepth)
        
        if (localSamplesDataCount == 0 || localSamplesDataCount == 0) {
            print("No show, no data")
            return;
        }
        
        /// use a mutable Data wrapper around pixelBuffer for output
        var frameData = Data(Array(repeating: 0, count: width * height * 4))

        /// access the buffers and call the C function
        localSamplesData.withUnsafeMutableBytes { samplesPointer in
            localFFTData.withUnsafeMutableBytes { fftPointer in
                frameData.withUnsafeMutableBytes { framePointer in
                    /// convert to UnsafeMutablePointer<UInt8>
                    let frame = framePointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let samples = samplesPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let fft = fftPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    
                    /// call the C render function with stable, mutable memory
                    render(
                        frame,
                        width,
                        height,
                        samples,
                        fft,
                        localSamplesDataCount,
                        localFFTDataCount,
                        renderBitdepth,
                        nil, /// presets buffer empty for now (unused in v1)
                        0.03, /// speed factor
                        currentTimeCASecs,
                        sampleRate
                    )
                    
                    print("Frame", frame)
                }
            }
        }
        
        /// after render modifies samplesData, update the original pixelBuffer
        pixelBuffer = [UInt8](frameData)
        
        /// create an NSImage from the updated pixelBuffer
        guard let image = createImageFromRGBAData(samplesData: pixelBuffer, width: width, height: height) else {
            print("Failed to create image from data")
            return
        }

        /// update the NSImageView with the new image
        imageView.image = image
    }
    
    private func createImageFromRGBAData(samplesData: [UInt8], width: Int, height: Int) -> NSImage? {
        
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: UnsafeMutableRawPointer(mutating: pixelBuffer),
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
