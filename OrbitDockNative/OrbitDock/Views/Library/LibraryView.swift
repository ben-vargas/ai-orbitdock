//
//  LibraryView.swift
//  OrbitDock
//
//  Session archive with compact toolbar and flat list on mobile.
//

import SwiftUI

struct LibraryView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(AppRouter.self) private var router

  let sessions: [RootSessionNode]
  var containerWidth: CGFloat?

  @State private var searchText = ""
  @State private var sort: ActiveSessionSort = .recent
  @State private var providerFilter: ActiveSessionProviderFilter = .all
  @State private var selectedEndpointId: UUID?
  @State private var collapsedGroups: Set<String> = []
  @State private var showFilterSheet = false

  private var layoutMode: DashboardLayoutMode {
    DashboardLayoutMode.current(
      horizontalSizeClass: horizontalSizeClass,
      containerWidth: containerWidth
    )
  }

  private var archiveState: LibraryArchiveState {
    LibraryArchivePlanner.state(
      sessions: sessions,
      searchText: searchText,
      providerFilter: providerFilter,
      selectedEndpointId: selectedEndpointId,
      sort: sort
    )
  }

  private var providerScopedSessions: [RootSessionNode] {
    archiveState.providerScopedSessions
  }

  private var endpointFacets: [LibraryEndpointFacet] {
    archiveState.endpointFacets
  }

  private var summary: LibraryArchiveSummary {
    archiveState.summary
  }

  private var hasActiveFilters: Bool {
    !searchText.isEmpty || providerFilter != .all || selectedEndpointId != nil
  }

  private var projectGroups: [LibraryProjectGroup] {
    archiveState.projectGroups
  }

  var body: some View {
    VStack(spacing: 0) {
      LibraryToolbar(
        layoutMode: layoutMode,
        hasActiveFilters: hasActiveFilters,
        summary: summary,
        endpointFacets: endpointFacets,
        providerScopedSessionCount: providerScopedSessions.count,
        searchText: $searchText,
        sort: $sort,
        providerFilter: $providerFilter,
        selectedEndpointId: $selectedEndpointId,
        showFilterSheet: $showFilterSheet
      )

      if projectGroups.isEmpty {
        LibraryEmptyState(hasActiveFilters: hasActiveFilters)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: layoutMode.isPhoneCompact ? Spacing.xs : Spacing.lg) {
            resultSummaryLine

            if layoutMode.isPhoneCompact {
              LibraryFlatList(
                projectGroups: projectGroups,
                onSelectSession: selectSession
              )
            } else {
              ForEach(projectGroups) { group in
                LibraryProjectSection(
                  group: group,
                  layoutMode: layoutMode,
                  isCollapsed: collapsedGroups.contains(group.id),
                  onToggleCollapsed: {
                    withAnimation(Motion.hover) {
                      if collapsedGroups.contains(group.id) {
                        collapsedGroups.remove(group.id)
                      } else {
                        collapsedGroups.insert(group.id)
                      }
                    }
                  },
                  onSelectSession: selectSession
                )
              }
            }
          }
          .padding(layoutMode.contentPadding)
        }
        .scrollContentBackground(.hidden)
      }
    }
    .sheet(isPresented: $showFilterSheet) {
      LibraryFilterSheet(
        providerFilter: $providerFilter,
        selectedEndpointId: $selectedEndpointId,
        endpointFacets: endpointFacets,
        providerScopedSessionCount: providerScopedSessions.count,
        onReset: resetFilters
      )
      .presentationDetents([.height(320), .medium])
      .presentationDragIndicator(.visible)
    }
  }

  // MARK: - Result Summary

  private var resultSummaryLine: some View {
    HStack(spacing: Spacing.xs) {
      Text("\(summary.sessionCount) sessions")
        .font(.system(size: TypeScale.caption, weight: .semibold))
        .foregroundStyle(Color.textTertiary)

      if !layoutMode.isPhoneCompact, summary.projectCount > 1 {
        Text("across \(summary.projectCount) projects")
          .font(.system(size: TypeScale.caption))
          .foregroundStyle(Color.textQuaternary)
      }

      if hasActiveFilters {
        Text("filtered")
          .font(.system(size: TypeScale.micro, weight: .bold, design: .rounded))
          .foregroundStyle(Color.accent)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.accent.opacity(OpacityTier.light), in: Capsule())
      }
    }
    .padding(.horizontal, layoutMode.isPhoneCompact ? Spacing.sm : Spacing.md)
  }

  // MARK: - Actions

  private func selectSession(_ session: RootSessionNode) {
    withAnimation(Motion.standard) {
      router.selectSession(session.sessionRef, source: .library)
    }
  }

  private func resetFilters() {
    providerFilter = .all
    selectedEndpointId = nil
  }
}
