import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ComposerImageAttachmentOptimizer {
  struct Policy: Equatable, Sendable {
    let hardMaxBytes: Int
    let preferredMaxBytes: Int
    let maxLongEdgePixels: Int
    let maxPixelCount: Int

    static func composer(isRemoteConnection: Bool) -> Self {
      Self(
        hardMaxBytes: ComposerImageAttachmentPolicy.maxSingleImageBytes,
        preferredMaxBytes: isRemoteConnection
          ? ComposerImageAttachmentPolicy.preferredRemoteSingleImageBytes
          : ComposerImageAttachmentPolicy.preferredLocalSingleImageBytes,
        maxLongEdgePixels: ComposerImageAttachmentPolicy.recommendedMaxLongEdgePixels,
        maxPixelCount: ComposerImageAttachmentPolicy.recommendedMaxPixelCount
      )
    }
  }

  struct Result: Equatable {
    let data: Data
    let mimeType: String
  }

  private struct SourceMetadata {
    let pixelWidth: Int
    let pixelHeight: Int

    var longEdgePixels: Int {
      max(pixelWidth, pixelHeight)
    }

    var pixelCount: Int {
      max(0, pixelWidth) * max(0, pixelHeight)
    }
  }

  private struct Candidate {
    let data: Data
    let mimeType: String
    let longEdgePixels: Int
  }

  static func optimize(
    imageData: Data,
    mimeType: String,
    policy: Policy
  ) -> Result? {
    guard policy.hardMaxBytes > 0, policy.preferredMaxBytes > 0 else { return nil }

    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions),
          let metadata = metadata(for: source)
    else {
      return imageData.count <= policy.hardMaxBytes ? Result(data: imageData, mimeType: mimeType) : nil
    }

    let targetLongEdge = recommendedLongEdge(for: metadata, policy: policy)
    let shouldNormalize =
      imageData.count > policy.preferredMaxBytes
      || imageData.count > policy.hardMaxBytes
      || metadata.longEdgePixels > targetLongEdge

    guard shouldNormalize else {
      return Result(data: imageData, mimeType: mimeType)
    }

    let prefersLossless = prefersLosslessEncoding(for: mimeType)
    var preferredCandidate: Candidate? = nil
    var fallbackCandidate: Candidate? = nil

    if let fullSizeImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
      for encoded in encodedCandidates(
        from: fullSizeImage,
        mimeType: mimeType,
        prefersLossless: prefersLossless
      ) {
        (preferredCandidate, fallbackCandidate) = updateBestCandidates(
          considering: Candidate(
            data: encoded.data,
            mimeType: encoded.mimeType,
            longEdgePixels: metadata.longEdgePixels
          ),
          preferredCandidate: preferredCandidate,
          fallbackCandidate: fallbackCandidate,
          policy: policy,
          targetLongEdge: targetLongEdge
        )
      }
    }

    for pixelSize in candidatePixelSizes(
      originalLongEdgePixels: metadata.longEdgePixels,
      targetLongEdgePixels: targetLongEdge
    ) {
      guard let cgImage = downsampledAttachmentImage(from: source, maxPixelSize: pixelSize) else {
        continue
      }

      for encoded in encodedCandidates(
        from: cgImage,
        mimeType: mimeType,
        prefersLossless: prefersLossless
      ) {
        (preferredCandidate, fallbackCandidate) = updateBestCandidates(
          considering: Candidate(
            data: encoded.data,
            mimeType: encoded.mimeType,
            longEdgePixels: max(cgImage.width, cgImage.height)
          ),
          preferredCandidate: preferredCandidate,
          fallbackCandidate: fallbackCandidate,
          policy: policy,
          targetLongEdge: targetLongEdge
        )
      }
    }

    let chosen = preferredCandidate ?? fallbackCandidate
    guard let chosen else {
      return imageData.count <= policy.hardMaxBytes ? Result(data: imageData, mimeType: mimeType) : nil
    }

    return Result(data: chosen.data, mimeType: chosen.mimeType)
  }

  static func imagePixelDimensions(from data: Data) -> (width: Int?, height: Int?) {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      return (nil, nil)
    }

    return (
      properties[kCGImagePropertyPixelWidth] as? Int,
      properties[kCGImagePropertyPixelHeight] as? Int
    )
  }

  private static func metadata(for source: CGImageSource) -> SourceMetadata? {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      return nil
    }

    let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    guard width > 0, height > 0 else { return nil }
    return SourceMetadata(pixelWidth: width, pixelHeight: height)
  }

  private static func recommendedLongEdge(
    for metadata: SourceMetadata,
    policy: Policy
  ) -> Int {
    guard metadata.longEdgePixels > 0 else { return policy.maxLongEdgePixels }

    let aspectLimitedLongEdge: Int
    if metadata.pixelCount > policy.maxPixelCount {
      let scale = sqrt(Double(policy.maxPixelCount) / Double(metadata.pixelCount))
      aspectLimitedLongEdge = max(1, Int(Double(metadata.longEdgePixels) * scale))
    } else {
      aspectLimitedLongEdge = metadata.longEdgePixels
    }

    return max(1, min(metadata.longEdgePixels, policy.maxLongEdgePixels, aspectLimitedLongEdge))
  }

  private static func updateBestCandidates(
    considering candidate: Candidate,
    preferredCandidate: Candidate?,
    fallbackCandidate: Candidate?,
    policy: Policy,
    targetLongEdge: Int
  ) -> (preferred: Candidate?, fallback: Candidate?) {
    guard candidate.data.count <= policy.hardMaxBytes else {
      return (preferredCandidate, fallbackCandidate)
    }

    let satisfiesPreferredBudget = candidate.data.count <= policy.preferredMaxBytes
    let satisfiesDimensionBudget = candidate.longEdgePixels <= targetLongEdge

    let nextPreferred: Candidate?
    if satisfiesPreferredBudget && satisfiesDimensionBudget {
      if let preferredCandidate, candidate.data.count >= preferredCandidate.data.count {
        nextPreferred = preferredCandidate
      } else {
        nextPreferred = candidate
      }
    } else {
      nextPreferred = preferredCandidate
    }

    let nextFallback: Candidate?
    if let fallbackCandidate, candidate.data.count >= fallbackCandidate.data.count {
      nextFallback = fallbackCandidate
    } else {
      nextFallback = candidate
    }

    return (nextPreferred, nextFallback)
  }

  private static func candidatePixelSizes(
    originalLongEdgePixels: Int,
    targetLongEdgePixels: Int
  ) -> [Int] {
    let searchUpperBound = min(originalLongEdgePixels, targetLongEdgePixels)
    guard searchUpperBound > 0 else { return [] }

    let baselineSizes = [8_192, 7_168, 6_144, 5_120, 4_096, 3_584, 3_072, 2_560, 2_048, 1_600, 1_280, 1_024, 768, 640]
    var seen: Set<Int> = []
    var candidates: [Int] = []

    if targetLongEdgePixels < originalLongEdgePixels {
      seen.insert(searchUpperBound)
      candidates.append(searchUpperBound)
    }

    for size in baselineSizes where size < searchUpperBound && !seen.contains(size) {
      seen.insert(size)
      candidates.append(size)
    }

    return candidates
  }

  private static func prefersLosslessEncoding(for mimeType: String) -> Bool {
    switch mimeType {
      case "image/png", "image/gif", "image/svg+xml":
        true
      default:
        false
    }
  }

  private static func downsampledAttachmentImage(
    from source: CGImageSource,
    maxPixelSize: Int
  ) -> CGImage? {
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
  }

  private static func encodedCandidates(
    from cgImage: CGImage,
    mimeType: String,
    prefersLossless: Bool
  ) -> [Result] {
    let jpegQualities: [CGFloat] = [0.92, 0.86, 0.8, 0.74, 0.68]
    var candidates: [Result] = []

    if prefersLossless, let pngData = encodedAttachmentData(from: cgImage, type: .png) {
      candidates.append(Result(data: pngData, mimeType: "image/png"))
    }

    for quality in jpegQualities {
      guard let jpegData = encodedAttachmentData(
        from: cgImage,
        type: .jpeg,
        compressionQuality: quality
      ) else { continue }
      candidates.append(Result(data: jpegData, mimeType: "image/jpeg"))
    }

    if !prefersLossless, let pngData = encodedAttachmentData(from: cgImage, type: .png) {
      candidates.append(Result(data: pngData, mimeType: "image/png"))
    }

    return candidates
  }

  private static func encodedAttachmentData(
    from cgImage: CGImage,
    type: UTType,
    compressionQuality: CGFloat? = nil
  ) -> Data? {
    let outputData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      outputData,
      type.identifier as CFString,
      1,
      nil
    ) else { return nil }

    var properties: [CFString: Any] = [:]
    if let compressionQuality, type == .jpeg {
      properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
    }

    CGImageDestinationAddImage(
      destination,
      cgImage,
      properties.isEmpty ? nil : properties as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else { return nil }
    return outputData as Data
  }
}
