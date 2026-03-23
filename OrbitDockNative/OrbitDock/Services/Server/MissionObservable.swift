//
//  MissionObservable.swift
//  OrbitDock
//
//  Per-mission @Observable state for live WebSocket updates.
//  Keyed by mission ID in SessionStore, matching the SessionObservable pattern.
//

import Foundation

@Observable
@MainActor
final class MissionObservable {
  let missionId: String

  var summary: MissionSummary?
  var issues: [MissionIssueItem] = []
  var deltaRevision: UInt64 = 0
  var nextTickAt: Date?
  var lastTickAt: Date?
  var heartbeatRevision: UInt64 = 0

  init(missionId: String) {
    self.missionId = missionId
  }
}
