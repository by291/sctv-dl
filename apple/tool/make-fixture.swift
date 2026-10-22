import AVFoundation
import Foundation

// Generate original synthetic media; no upstream episode is copied into the test bundle.
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "apple/build/fixtures/probe.mp4")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180,
])
writer.add(input)
guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
writer.startSession(atSourceTime: .zero)

for frame in 0..<360 {
    while !input.isReadyForMoreMediaData {
        guard writer.status == .writing else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        try await Task.sleep(for: .milliseconds(5))
    }
    var buffer: CVPixelBuffer?
    guard let pool = adaptor.pixelBufferPool,
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
        let buffer else { throw CocoaError(.fileWriteUnknown) }
    CVPixelBufferLockBaseAddress(buffer, [])
    let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for row in 0..<180 {
        for column in 0..<320 {
            let index = row * stride + column * 4
            bytes[index] = 255
            bytes[index + 1] = UInt8((column + frame) % 256)
            bytes[index + 2] = UInt8((row + frame) % 256)
            bytes[index + 3] = 180
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
        throw writer.error ?? CocoaError(.fileWriteUnknown)
    }
}
input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
print(output.path)
