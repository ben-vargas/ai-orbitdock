//
//  LibraryFlatList.swift
//  OrbitDock
//
//  Flat session list for phoneCompact library view.
//  Lightweight project name headers + FlatSessionRow rows, no collapse or subsections.
//

import SwiftUI

struct LibraryFlatList: View {
  let projectGroups: [LibraryProjectGroup]
  let onSelectSession: (RootSessionNode) -> Void

  var body: some View {
    ForEach(projectGroups) { group in
      projectHeader(group)

      let allSessions = group.liveSessions + group.archivedSessions
      ForEach(allSessions, id: \.scopedID) { session in
        FlatSessionRow(
          session: session,
          onSelect: { onSelectSession(session) },
          isAttentionPromoted: session.needsAttention
        )
      }
    }
  }

  private func projectHeader(_ group: LibraryProjectGroup) -> some View {
    HStack(spacing: Spacing.xs) {
      Text(group.name)
        .font(.system(size: TypeScale.caption, weight: .bold))
        .foregroundStyle(Color.textSecondary)
        .lineLimit(1)

      LibraryCountPill(text: "\(group.totalSessionCount)", tint: .textTertiary)

      if group.liveSessions.count > 0 {
        LibraryInlineStat(
          text: "\(group.liveSessions.count) live",
          tint: .statusWorking
        )
      }

      Spacer()
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.top, Spacing.md)
    .padding(.bottom, Spacing.xs)
  }
}
