import AppKit
import MetalKit

struct RenderSize {
    var width: Int
    var height: Int
}

class DetachedViewController: NSViewController, NSWindowDelegate, MTKViewDelegate {
    var metalView: MTKView!
    var fpsLabel: NSTextField!
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer!
    var inputTexture: MTLTexture?

    private var pixelBufferA: [UInt8] = []
    private var pixelBufferB: [UInt8] = []
    private var useBufferA = true
    private let frameSemaphore = DispatchSemaphore(value: 1)

    var config: VisualizationConfig?
    var renderSize: RenderSize?
    private var isMetalInitialized = false
    private var needsTextureUpdate = false

    // Shared buffer index
    var bufferIndex = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bufferIndex.pointee = -1 // Initialize bufferIndex to -1
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("Metal is not supported on this device.")
            return
        }
        setupFPSLabel()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.delegate = self
    }
    
    func windowWillClose(_ notification: Notification) {
        // Terminate the app when the window closes
        NSApplication.shared.terminate(nil)
    }
    
    func initializeMetal() {
        guard !isMetalInitialized else { return }
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device.")
            return
        }
        self.device = metalDevice
        setupMetalView()
        setupPipeline()
        setupVertexBuffer()
        isMetalInitialized = true
    }

    func setupMetalView() {
        metalView = MTKView(frame: view.bounds, device: device)
        metalView.autoresizingMask = [.width, .height]
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        metalView.delegate = self
        metalView.autoResizeDrawable = true
        metalView.isPaused = false
        view.addSubview(metalView)
        
        // Use Auto Layout to make metalView fill the entire view
        metalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func setupPipeline() {
        commandQueue = device.makeCommandQueue()
        let library = device.makeDefaultLibrary()
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library?.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "fragment_main")
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat

        // Set up the vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        // Position attribute
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // Texture coordinate attribute
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 4
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Set up buffer layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 6
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    func setupVertexBuffer() {
        let vertices: [Float] = [
            // Positions         // Texture Coordinates
            -1.0, -1.0, 0.0, 1.0,   0.0, 1.0,
             1.0, -1.0, 0.0, 1.0,   1.0, 1.0,
            -1.0,  1.0, 0.0, 1.0,   0.0, 0.0,
             1.0,  1.0, 0.0, 1.0,   1.0, 0.0
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
    }

    func setupFPSLabel() {
        fpsLabel = NSTextField(labelWithString: "FPS: 0")
        fpsLabel.frame = NSRect(x: 10, y: 10, width: 100, height: 20)
        fpsLabel.textColor = NSColor.white
        fpsLabel.font = NSFont.systemFont(ofSize: 14)
        fpsLabel.isEditable = false
        fpsLabel.isBezeled = false
        fpsLabel.drawsBackground = false
        view.addSubview(fpsLabel)
    }

    func setVisualizationConfig(config: VisualizationConfig) {
        self.config = config
        determineRenderSize()
        initializeMetal()

        guard let renderSize = renderSize else { return }

        let bufferSize = renderSize.width * renderSize.height * 4
        pixelBufferA = Array(repeating: 0, count: bufferSize)
        pixelBufferB = Array(repeating: 0, count: bufferSize)

        // Obtain pointers to the pixel buffers
        let framePointerA: UnsafeMutablePointer<UInt8> = pixelBufferA.withUnsafeMutableBufferPointer { bufferPointer in
            return bufferPointer.baseAddress!
        }

        let framePointerB: UnsafeMutablePointer<UInt8> = pixelBufferB.withUnsafeMutableBufferPointer { bufferPointer in
            return bufferPointer.baseAddress!
        }

        // Compute frame interval in microseconds
        let frameInterval = Int(1_000_000 / config.targetFPS)

        // Start the continuous render loop in C
        startContinuousRender(
            framePointerA,
            framePointerB,
            bufferIndex, // Pass the pointer to bufferIndex
            renderSize.width,
            renderSize.height,
            UInt8(config.bitDepth),
            44100,
            frameInterval,
            Int(config.targetFPS)
        )

        // Timer to trigger frame rendering
        Timer.scheduledTimer(withTimeInterval: 1.0 / Double(config.targetFPS), repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.frameSemaphore.wait()
            // Read the bufferIndex set by the C code
            let index = self.bufferIndex.pointee
            if index == 0 || index == 1 {
                self.useBufferA = (index == 0)
                self.needsTextureUpdate = true
                self.metalView.setNeedsDisplay(self.metalView.bounds)
                // Reset bufferIndex to prevent rereading the same frame
                self.bufferIndex.pointee = -1
            } else {
                // No new frame; release the semaphore
                self.frameSemaphore.signal()
            }
        }
    }

    func determineRenderSize() {
        if let config = config {
            renderSize = RenderSize(
                width: Int(Double(config.width) * config.oversamplingFactor),
                height: Int(Double(config.height) * config.oversamplingFactor)
            )
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Update any necessary configurations when the drawable size changes
    }

    func draw(in view: MTKView) {
        renderOnCanvas()
    }

    func renderOnCanvas() {
        guard needsTextureUpdate,
              let drawable = metalView.currentDrawable,
              let renderPassDescriptor = metalView.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            frameSemaphore.signal()
            return
        }

        needsTextureUpdate = false

        let activePixelBuffer = useBufferA ? pixelBufferA : pixelBufferB
        guard let renderSize = renderSize else {
            frameSemaphore.signal()
            return
        }

        if inputTexture == nil || inputTexture?.width != renderSize.width || inputTexture?.height != renderSize.height {
            inputTexture = texture(fromRGBAData: activePixelBuffer, width: renderSize.width, height: renderSize.height)
        } else {
            updateTexture(inputTexture!, withData: activePixelBuffer, width: renderSize.width, height: renderSize.height)
        }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(inputTexture, index: 0)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setViewport(MTLViewport(
            originX: 0.0,
            originY: 0.0,
            width: Double(metalView.drawableSize.width),
            height: Double(metalView.drawableSize.height),
            znear: 0.0,
            zfar: 1.0
        ))

        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func texture(fromRGBAData data: [UInt8], width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        updateTexture(texture, withData: data, width: width, height: height)
        return texture
    }

    func updateTexture(_ texture: MTLTexture, withData data: [UInt8], width: Int, height: Int) {
        let region = MTLRegionMake2D(0, 0, width, height)
        data.withUnsafeBytes { bytes in
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: width * 4)
        }
    }
}
