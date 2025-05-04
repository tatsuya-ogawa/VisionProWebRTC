#if os(visionOS)
import ARKit
import AVFoundation
import Foundation
import WebRTC
class VisionProRTCVideoCapturer :RTCVideoCapturer {
    let videoSource:RTCVideoSource
    func convertToBGRA(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // Core Image コンテキストを作成
        let ciContext = CIContext()

        // YUV ピクセルバッファから CIImage を作成
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)

        // 新しい BGRA ピクセルバッファを作成
        var newPixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: CVPixelBufferGetWidth(pixelBuffer),
            kCVPixelBufferHeightKey as String: CVPixelBufferGetHeight(pixelBuffer),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &newPixelBuffer)

        guard let outputPixelBuffer = newPixelBuffer else {
            return nil
        }

        // BGRA にレンダリング
        ciContext.render(ciImage, to: outputPixelBuffer)

        return outputPixelBuffer
    }
    func copyPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // Lock the base address of the original pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        // Get the pixel buffer's properties
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        // Create a new pixel buffer to copy into
        var newPixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(nil, width, height, pixelFormat, nil, &newPixelBuffer)
        
        if result != kCVReturnSuccess {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }
        
        // Lock the base address of the new pixel buffer
        CVPixelBufferLockBaseAddress(newPixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        // Get base addresses
        let srcBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let destBaseAddress = CVPixelBufferGetBaseAddress(newPixelBuffer!)
        
        // Get the total size of the pixel buffer (assume planar formats are not used here)
        let dataSize = CVPixelBufferGetDataSize(pixelBuffer)
        
        // Copy the pixel data
        memcpy(destBaseAddress, srcBaseAddress, dataSize)
        
        // Unlock the base addresses
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferUnlockBaseAddress(newPixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return newPixelBuffer
    }
    init(delegate:RTCVideoSource) {
        self.videoSource = delegate
        super.init()
    }
    var lastCalledTime: Date?
    var lastCalledBuffer:CVPixelBuffer?
    func startCapture() async {
        let formats = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left])
        let arKitSession = ARKitSession()
        let status = await arKitSession.queryAuthorization(for: [.cameraAccess])
        let cameraTracking = CameraFrameProvider()
        do { try await arKitSession.run([cameraTracking]) } catch{
            print("arKitSession.run error")
            return
        }

        // Then receive the new camera frame:
        for await i in cameraTracking.cameraFrameUpdates(
            for: formats.first!)!
        {
            let imageBuffer: CVPixelBuffer = i.primarySample.pixelBuffer
            let currentTime = Date()

            // Skip if the last call was less than X second ago
            let skipSeconds = 0.1
            if lastCalledTime == nil || currentTime.timeIntervalSince(lastCalledTime!) >= skipSeconds {
                lastCalledTime = currentTime
            }
            self.lastCalledBuffer = self.convertToBGRA(pixelBuffer: imageBuffer)
            
            if let lastCalledBuffer = self.lastCalledBuffer {
                let rtcpixelBuffer = RTCCVPixelBuffer(pixelBuffer: lastCalledBuffer)
               // これが映像フレームのデータ
               let videoFrame = RTCVideoFrame(
                   buffer: rtcpixelBuffer,
                   rotation: RTCVideoRotation._0,
                   timeStampNs: Int64(Date().timeIntervalSince1970 * 1_000_000_000)
               )
               videoSource.capturer(self, didCapture: videoFrame)
            }
        }
    }
}
#endif
