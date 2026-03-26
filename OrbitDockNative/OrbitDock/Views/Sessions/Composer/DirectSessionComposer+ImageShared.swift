//
//  DirectSessionComposer+ImageShared.swift
//  OrbitDock
//

import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension DirectSessionComposer {
  var shouldEncodeLocalFileImagesAsDataURI: Bool {
    false
  }

  @discardableResult
  func appendAttachedImage(_ attached: AttachedImage) -> Bool {
    let isDuplicate = attachmentState.images.contains {
      $0.uploadMimeType == attached.uploadMimeType
        && $0.uploadData == attached.uploadData
    }
    guard !isDuplicate else { return false }

    let usedRawBytes = ComposerImageAttachmentPolicy.usedRawBytes(
      attachmentState.images.map(\.uploadData.count)
    )
    let validation = ComposerImageAttachmentPolicy.validateAddition(
      existingCount: attachmentState.images.count,
      usedRawBytes: usedRawBytes,
      candidateRawBytes: attached.uploadData.count
    )
    guard validation == .allowed else {
      errorMessage = ComposerImageAttachmentPolicy.message(for: validation)
      Platform.services.playHaptic(.error)
      requestComposerFocus()
      return false
    }

    withAnimation(Motion.gentle) {
      if let errorMessage, ComposerImageAttachmentPolicy.isPolicyMessage(errorMessage) {
        self.errorMessage = nil
      }
      attachmentState.images.append(attached)
    }
    return true
  }

  @discardableResult
  func appendImageAttachment(
    thumbnail: PlatformImage,
    imageData: Data,
    mimeType: String,
    displayName: String? = nil
  ) -> Bool {
    guard let preparedPayload = optimizedAttachmentPayload(
      imageData: imageData,
      mimeType: mimeType,
      policy: .composer(isRemoteConnection: viewModel.isRemoteConnection)
    ) else {
      errorMessage = ComposerImageAttachmentPolicy.message(
        for: .tooLarge(maxBytes: ComposerImageAttachmentPolicy.maxSingleImageBytes)
      )
      Platform.services.playHaptic(.error)
      requestComposerFocus()
      return false
    }

    let dimensions = imagePixelDimensions(from: preparedPayload.data)
    let attached = AttachedImage(
      id: UUID().uuidString,
      thumbnail: thumbnail,
      uploadData: preparedPayload.data,
      uploadMimeType: preparedPayload.mimeType,
      displayName: displayName,
      pixelWidth: dimensions.width,
      pixelHeight: dimensions.height
    )
    return appendAttachedImage(attached)
  }

  func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
      case "png": "image/png"
      case "jpg", "jpeg": "image/jpeg"
      case "gif": "image/gif"
      case "webp": "image/webp"
      case "heic": "image/heic"
      case "heif": "image/heif"
      case "svg": "image/svg+xml"
      case "bmp": "image/bmp"
      case "tiff", "tif": "image/tiff"
      default: "image/png"
    }
  }

  func isImageFileURL(_ url: URL) -> Bool {
    guard !url.pathExtension.isEmpty else { return false }
    guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
      return false
    }
    return type.conforms(to: .image)
  }

  @discardableResult
  func appendLocalFileImage(
    url: URL,
    thumbnail: PlatformImage,
    encodeAsDataURI: Bool
  ) -> Bool {
    _ = encodeAsDataURI
    guard let data = try? Data(contentsOf: url) else { return false }
    return appendImageAttachment(
      thumbnail: thumbnail,
      imageData: data,
      mimeType: mimeType(for: url),
      displayName: url.lastPathComponent
    )
  }

  func optimizedAttachmentPayload(
    imageData: Data,
    mimeType: String,
    policy: ComposerImageAttachmentOptimizer.Policy
  ) -> (data: Data, mimeType: String)? {
    guard let result = ComposerImageAttachmentOptimizer.optimize(
      imageData: imageData,
      mimeType: mimeType,
      policy: policy
    ) else {
      return nil
    }
    return (result.data, result.mimeType)
  }

  func imagePixelDimensions(from data: Data) -> (width: Int?, height: Int?) {
    ComposerImageAttachmentOptimizer.imagePixelDimensions(from: data)
  }
}
