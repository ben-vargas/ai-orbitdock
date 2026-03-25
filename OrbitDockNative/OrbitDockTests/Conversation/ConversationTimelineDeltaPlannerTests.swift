import Foundation
@testable import OrbitDock
import Testing

struct ConversationTimelineDeltaPlannerTests {
  @Test func prependOnlyDoesNotCountAsLatestAppend() {
    let oldEntries = [
      makeEntry(id: "2", sequence: 2),
      makeEntry(id: "3", sequence: 3),
    ]
    let newEntries = [
      makeEntry(id: "1", sequence: 1),
      makeEntry(id: "2", sequence: 2),
      makeEntry(id: "3", sequence: 3),
    ]

    #expect(
      ConversationTimelineDeltaPlanner.latestAppendedCount(
        oldEntries: oldEntries,
        newEntries: newEntries
      ) == 0
    )
  }

  @Test func appendOnlyCountsNewTailEntries() {
    let oldEntries = [
      makeEntry(id: "1", sequence: 1),
      makeEntry(id: "2", sequence: 2),
    ]
    let newEntries = [
      makeEntry(id: "1", sequence: 1),
      makeEntry(id: "2", sequence: 2),
      makeEntry(id: "3", sequence: 3),
      makeEntry(id: "4", sequence: 4),
    ]

    #expect(
      ConversationTimelineDeltaPlanner.latestAppendedCount(
        oldEntries: oldEntries,
        newEntries: newEntries
      ) == 2
    )
  }

  @Test func mixedPrependAndAppendCountsOnlyLatestTailEntries() {
    let oldEntries = [
      makeEntry(id: "3", sequence: 3),
      makeEntry(id: "4", sequence: 4),
    ]
    let newEntries = [
      makeEntry(id: "1", sequence: 1),
      makeEntry(id: "2", sequence: 2),
      makeEntry(id: "3", sequence: 3),
      makeEntry(id: "4", sequence: 4),
      makeEntry(id: "5", sequence: 5),
    ]

    #expect(
      ConversationTimelineDeltaPlanner.latestAppendedCount(
        oldEntries: oldEntries,
        newEntries: newEntries
      ) == 1
    )
  }

  private func makeEntry(id: String, sequence: UInt64) -> ServerConversationRowEntry {
    ServerConversationRowEntry(
      sessionId: "session-1",
      sequence: sequence,
      turnId: nil,
      row: .notice(ServerConversationNoticeRow(
        id: id,
        kind: .generic,
        severity: .info,
        title: "Entry \(id)",
        summary: nil,
        body: nil,
        renderHints: .init()
      ))
    )
  }
}
