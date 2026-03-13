import AppKit
import CoreImage
import Input
import MetalKit

public enum LibretroPixelFormat: Int32 {
    case rgb1555 = 0
    case xrgb8888 = 1
    case rgb565 = 2
}

public final class MetalRenderer: NSObject, ObservableObject, MTKViewDelegate, @unchecked Sendable {
    private struct Frame {
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var pixels: Data
    }

    public let device: MTLDevice?
    private let ciContext: CIContext?
    private let commandQueue: MTLCommandQueue?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let lock = NSLock()
    private var latestFrame: Frame?
    private var drawableSize = CGSize(width: 640, height: 480)
    private var preferredAspectRatio: CGFloat?
    public var sharpPixelsEnabled = true

    public override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.ciContext = device.map { CIContext(mtlDevice: $0) }
        self.commandQueue = device?.makeCommandQueue()
        super.init()
    }

    public var isSupported: Bool {
        device != nil && ciContext != nil
    }

    public func updateFrame(buffer: UnsafeRawPointer, width: Int, height: Int, pitch: Int, format: LibretroPixelFormat) {
        let bytes = convertToBGRA(buffer: buffer, width: width, height: height, pitch: pitch, format: format)
        lock.lock()
        latestFrame = Frame(width: width, height: height, bytesPerRow: width * 4, pixels: bytes)
        lock.unlock()
    }

    public func updateGeometry(baseWidth: Int, baseHeight: Int, aspectRatio: Double) {
        lock.lock()
        if aspectRatio > 0 {
            preferredAspectRatio = CGFloat(aspectRatio)
        } else if baseWidth > 0, baseHeight > 0 {
            preferredAspectRatio = CGFloat(baseWidth) / CGFloat(baseHeight)
        } else {
            preferredAspectRatio = nil
        }
        lock.unlock()
    }

    public func draw(in view: MTKView) {
        guard
            let context = ciContext,
            let drawable = view.currentDrawable,
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        lock.lock()
        let frame = latestFrame
        let preferredAspectRatio = preferredAspectRatio
        lock.unlock()

        guard let frame else {
            return
        }

        guard
            let provider = CGDataProvider(data: frame.pixels as CFData),
            let image = CGImage(
                width: frame.width,
                height: frame.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: frame.bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return
        }

        let aspectRatio: CGFloat
        if let preferredAspectRatio, preferredAspectRatio > 0 {
            aspectRatio = preferredAspectRatio
        } else {
            aspectRatio = CGFloat(frame.width) / CGFloat(max(frame.height, 1))
        }

        let targetRect = aspectFitRect(contentAspectRatio: aspectRatio, containerSize: drawableSize)
        let scaleX = targetRect.width / CGFloat(frame.width)
        let scaleY = targetRect.height / CGFloat(frame.height)
        let sourceImage = CIImage(cgImage: image)
        let sampledImage = sharpPixelsEnabled ? sourceImage.samplingNearest() : sourceImage
        let transformedImage = sampledImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: targetRect.origin.x, y: targetRect.origin.y))

        context.render(
            transformedImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: drawableSize),
            colorSpace: colorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }

    private func convertToBGRA(buffer: UnsafeRawPointer, width: Int, height: Int, pitch: Int, format: LibretroPixelFormat) -> Data {
        var output = Data(count: width * height * 4)
        output.withUnsafeMutableBytes { destination in
            guard let dstBase = destination.baseAddress else {
                return
            }

            for y in 0 ..< height {
                let srcRow = buffer.advanced(by: y * pitch)
                let dstRow = dstBase.advanced(by: y * width * 4)

                switch format {
                case .xrgb8888:
                    let sourcePixels = srcRow.bindMemory(to: UInt32.self, capacity: width)
                    let targetPixels = dstRow.bindMemory(to: UInt32.self, capacity: width)
                    for x in 0 ..< width {
                        let pixel = sourcePixels[x]
                        let r = UInt8((pixel >> 16) & 0xFF)
                        let g = UInt8((pixel >> 8) & 0xFF)
                        let b = UInt8(pixel & 0xFF)
                        targetPixels[x] = (UInt32(0xFF) << 24) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)
                    }
                case .rgb565:
                    let sourcePixels = srcRow.bindMemory(to: UInt16.self, capacity: width)
                    let targetPixels = dstRow.bindMemory(to: UInt32.self, capacity: width)
                    for x in 0 ..< width {
                        let pixel = sourcePixels[x]
                        let r = UInt8(((pixel >> 11) & 0x1F) * 255 / 31)
                        let g = UInt8(((pixel >> 5) & 0x3F) * 255 / 63)
                        let b = UInt8((pixel & 0x1F) * 255 / 31)
                        targetPixels[x] = (UInt32(0xFF) << 24) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)
                    }
                case .rgb1555:
                    let sourcePixels = srcRow.bindMemory(to: UInt16.self, capacity: width)
                    let targetPixels = dstRow.bindMemory(to: UInt32.self, capacity: width)
                    for x in 0 ..< width {
                        let pixel = sourcePixels[x]
                        let r = UInt8(((pixel >> 10) & 0x1F) * 255 / 31)
                        let g = UInt8(((pixel >> 5) & 0x1F) * 255 / 31)
                        let b = UInt8((pixel & 0x1F) * 255 / 31)
                        targetPixels[x] = (UInt32(0xFF) << 24) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)
                    }
                }
            }
        }
        return output
    }

    private func aspectFitRect(contentAspectRatio: CGFloat, containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0, contentAspectRatio > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let containerAspectRatio = containerSize.width / containerSize.height
        if containerAspectRatio > contentAspectRatio {
            let height = containerSize.height
            let width = height * contentAspectRatio
            let x = (containerSize.width - width) * 0.5
            return CGRect(x: x, y: 0, width: width, height: height)
        }

        let width = containerSize.width
        let height = width / contentAspectRatio
        let y = (containerSize.height - height) * 0.5
        return CGRect(x: 0, y: y, width: width, height: height)
    }
}

public final class EmulatorMetalView: MTKView {
    private let inputManager: InputManager

    public init(renderer: MetalRenderer, inputManager: InputManager) {
        self.inputManager = inputManager
        super.init(frame: .zero, device: renderer.device)
        delegate = renderer
        autoresizingMask = [.width, .height]
        framebufferOnly = false
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 60
        clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var acceptsFirstResponder: Bool {
        true
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    public override func layout() {
        super.layout()
        drawableSize = bounds.size
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        inputManager.setKeyEvent(event, isDown: true)
    }

    public override func keyUp(with event: NSEvent) {
        inputManager.setKeyEvent(event, isDown: false)
    }
}
