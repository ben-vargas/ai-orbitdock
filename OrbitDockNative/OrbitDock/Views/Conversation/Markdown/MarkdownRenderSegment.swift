//
//  MarkdownRenderSegment.swift
//  OrbitDock
//
//  Stable render model for conversation markdown.
//  The projector groups semantic markdown blocks into a small set of
//  render segments so the eventual SwiftUI renderer can keep identity
//  stable while streaming content updates arrive.
//

import Foundation

enum MarkdownRenderSegment: Equatable {
  case prose(Prose)
  case codeBlock(CodeBlock)
  case table(Table)
  case thematicBreak(ThematicBreak)

  enum Kind: String, Hashable {
    case prose
    case codeBlock
    case table
    case thematicBreak
  }

  struct Identity: Hashable {
    let kind: Kind
    let startBlockIndex: Int
  }

  struct Prose: Equatable {
    let identity: Identity
    let sourceBlockRange: Range<Int>
    let blocks: [MarkdownBlock]
  }

  struct CodeBlock: Equatable {
    let identity: Identity
    let sourceBlockRange: Range<Int>
    let language: String?
    let code: String
  }

  struct Table: Equatable {
    let identity: Identity
    let sourceBlockRange: Range<Int>
    let headers: [String]
    let rows: [[String]]
  }

  struct ThematicBreak: Equatable {
    let identity: Identity
    let sourceBlockRange: Range<Int>
  }

  var kind: Kind {
    switch self {
      case .prose:
        .prose
      case .codeBlock:
        .codeBlock
      case .table:
        .table
      case .thematicBreak:
        .thematicBreak
    }
  }

  var identity: Identity {
    switch self {
      case let .prose(segment):
        segment.identity
      case let .codeBlock(segment):
        segment.identity
      case let .table(segment):
        segment.identity
      case let .thematicBreak(segment):
        segment.identity
    }
  }

  var sourceBlockRange: Range<Int> {
    switch self {
      case let .prose(segment):
        segment.sourceBlockRange
      case let .codeBlock(segment):
        segment.sourceBlockRange
      case let .table(segment):
        segment.sourceBlockRange
      case let .thematicBreak(segment):
        segment.sourceBlockRange
    }
  }

  var startBlockIndex: Int {
    identity.startBlockIndex
  }

  var leadingBlock: MarkdownBlock? {
    switch self {
      case let .prose(segment):
        segment.blocks.first
      case let .codeBlock(segment):
        .codeBlock(language: segment.language, code: segment.code)
      case let .table(segment):
        .table(headers: segment.headers, rows: segment.rows)
      case .thematicBreak:
        .thematicBreak
    }
  }

  var trailingBlock: MarkdownBlock? {
    switch self {
      case let .prose(segment):
        segment.blocks.last
      case let .codeBlock(segment):
        .codeBlock(language: segment.language, code: segment.code)
      case let .table(segment):
        .table(headers: segment.headers, rows: segment.rows)
      case .thematicBreak:
        .thematicBreak
    }
  }
}
