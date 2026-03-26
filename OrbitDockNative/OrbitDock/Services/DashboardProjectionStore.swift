import Foundation
import Observation

@MainActor
@Observable
final class DashboardProjectionStore {
  @ObservationIgnored weak var runtimeRegistry: ServerRuntimeRegistry?
  @ObservationIgnored var isDemoOverrideActive = false
  var rootSessions: [RootSessionNode] = []
  var dashboardConversations: [DashboardConversationRecord] = []
  var hasMultipleEndpoints = false
  var counts = DashboardTriageCounts(conversations: [])
  var directCount = 0
  var refreshIdentity = "dashboard-unbound"

  func apply(_ snapshot: DashboardProjectionSnapshot) {
    guard !isDemoOverrideActive else { return }
    rootSessions = snapshot.rootSessions
    dashboardConversations = snapshot.dashboardConversations
    hasMultipleEndpoints = snapshot.hasMultipleEndpoints
    counts = snapshot.counts
    directCount = snapshot.directCount
    refreshIdentity = snapshot.refreshIdentity
  }

  func applyDemo(_ snapshot: DashboardProjectionSnapshot) {
    isDemoOverrideActive = true
    rootSessions = snapshot.rootSessions
    dashboardConversations = snapshot.dashboardConversations
    hasMultipleEndpoints = snapshot.hasMultipleEndpoints
    counts = snapshot.counts
    directCount = snapshot.directCount
    refreshIdentity = snapshot.refreshIdentity
  }

  func clearDemoOverride() {
    isDemoOverrideActive = false
  }

  func refreshDashboardData() async {
    guard !isDemoOverrideActive, let runtimeRegistry else { return }
    await runtimeRegistry.refreshDashboardConversations()
  }
}

struct DashboardProjectionSnapshot: Sendable {
  let rootSessions: [RootSessionNode]
  let dashboardConversations: [DashboardConversationRecord]
  let hasMultipleEndpoints: Bool
  let counts: DashboardTriageCounts
  let directCount: Int
  let refreshIdentity: String

  static let empty = DashboardProjectionSnapshot(
    rootSessions: [],
    dashboardConversations: [],
    hasMultipleEndpoints: false,
    counts: DashboardTriageCounts(conversations: []),
    directCount: 0,
    refreshIdentity: "dashboard-unbound"
  )
}

enum DashboardProjectionBuilder {
  nonisolated static func build(
    rootSessions: [RootSessionNode],
    dashboardConversations: [DashboardConversationRecord],
    refreshIdentity: String
  ) -> DashboardProjectionSnapshot {
    DashboardProjectionSnapshot(
      rootSessions: rootSessions,
      dashboardConversations: dashboardConversations,
      hasMultipleEndpoints: Set(dashboardConversations.map(\.sessionRef.endpointId)).count > 1,
      counts: DashboardTriageCounts(conversations: dashboardConversations),
      directCount: dashboardConversations.filter(\.isDirect).count,
      refreshIdentity: refreshIdentity
    )
  }
}
