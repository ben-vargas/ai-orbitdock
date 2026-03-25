import Foundation
import Observation

@MainActor
@Observable
final class MissionProjectionStore {
  var missions: [AggregatedMissionSummary] = []

  func apply(_ snapshot: MissionProjectionSnapshot) {
    missions = snapshot.missions
  }
}

struct MissionProjectionSnapshot: Sendable {
  let missions: [AggregatedMissionSummary]

  static let empty = MissionProjectionSnapshot(missions: [])
}
