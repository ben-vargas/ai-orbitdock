import CoreGraphics
import Foundation
import ImageIO
@testable import OrbitDock
import Testing
import UniformTypeIdentifiers

struct ComposerImageAttachmentOptimizerTests {
  @Test func tallScreenshotLikePngIsDownsampledEvenWhenUnderHardByteCap() throws {
    let pngData = try makeStripedPNG(width: 1_280, height: 9_200)
    #expect(pngData.count < ComposerImageAttachmentPolicy.maxSingleImageBytes)

    let optimized = ComposerImageAttachmentOptimizer.optimize(
      imageData: pngData,
      mimeType: "image/png",
      policy: .composer(isRemoteConnection: false)
    )

    #expect(optimized != nil)

    let dimensions = ComposerImageAttachmentOptimizer.imagePixelDimensions(from: optimized!.data)
    let longEdge = max(dimensions.width ?? 0, dimensions.height ?? 0)

    #expect(longEdge <= ComposerImageAttachmentPolicy.recommendedMaxLongEdgePixels)
    #expect(optimized!.data.count <= ComposerImageAttachmentPolicy.maxSingleImageBytes)
  }

  @Test func remoteTransportBudgetPrefersSmallerEncodingBeforeHardLimit() throws {
    let pngData = try makeNoisePNG(width: 1_800, height: 1_800)
    #expect(pngData.count > ComposerImageAttachmentPolicy.preferredRemoteSingleImageBytes)
    #expect(pngData.count < ComposerImageAttachmentPolicy.maxSingleImageBytes)

    let optimized = ComposerImageAttachmentOptimizer.optimize(
      imageData: pngData,
      mimeType: "image/png",
      policy: .composer(isRemoteConnection: true)
    )

    #expect(optimized != nil)
    #expect(optimized!.data.count <= ComposerImageAttachmentPolicy.preferredRemoteSingleImageBytes)
    #expect(optimized!.data.count < pngData.count)
  }

  private func makeStripedPNG(width: Int, height: Int) throws -> Data {
    try makePNG(width: width, height: height) { x, y in
      let stripe = ((x / 32) + (y / 48)) % 6
      let base = UInt8(30 + stripe * 35)
      return (base, UInt8(min(255, Int(base) + 20)), UInt8(min(255, Int(base) + 40)), 255)
    }
  }

  private func makeNoisePNG(width: Int, height: Int) throws -> Data {
    try makePNG(width: width, height: height) { x, y in
      let seed = UInt64(bitPattern: Int64(x &* 73_856_093 ^ y &* 19_349_663))
      let mixed = splitMix64(seed)
      let red = UInt8(truncatingIfNeeded: mixed)
      let green = UInt8(truncatingIfNeeded: mixed >> 8)
      let blue = UInt8(truncatingIfNeeded: mixed >> 16)
      return (red, green, blue, 255)
    }
  }

  private func makePNG(
    width: Int,
    height: Int,
    pixel: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8)
  ) throws -> Data {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)

    for y in 0..<height {
      for x in 0..<width {
        let offset = y * bytesPerRow + x * bytesPerPixel
        let rgba = pixel(x, y)
        buffer[offset] = rgba.0
        buffer[offset + 1] = rgba.1
        buffer[offset + 2] = rgba.2
        buffer[offset + 3] = rgba.3
      }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let provider = CGDataProvider(data: Data(buffer) as CFData)
    #expect(provider != nil)

    guard let provider,
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          )
    else {
      Issue.record("Failed to create CGImage fixture")
      return Data()
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      output,
      UTType.png.identifier as CFString,
      1,
      nil
    ) else {
      Issue.record("Failed to create PNG destination")
      return Data()
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      Issue.record("Failed to encode PNG fixture")
      return Data()
    }

    return output as Data
  }

  private func splitMix64(_ seed: UInt64) -> UInt64 {
    var value = seed &+ 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
