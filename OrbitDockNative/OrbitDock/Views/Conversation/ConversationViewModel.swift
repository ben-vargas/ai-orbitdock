import Observation
import SwiftUI

@MainActor
@Observable
final class ConversationViewModel {
  var hasShownContent = false
  var currentSessionId: String?
  var currentSessionStore = SessionStore.preview()
  var currentViewMode: ChatViewMode = .focused
  var timeline: ConversationTimelinePresentation?
  var timelineViewModel = ConversationTimelineViewModel()
  var latestAppendEvent: ConversationLatestAppendEvent?
  var loadState: ConversationLoadState = .empty
  var forkOrigin: ConversationForkOriginPresentation?

  @ObservationIgnored private var sessionObservationGeneration: UInt64 = 0

  private let pageSize = 50

  func bind(sessionId: String?, sessionStore: SessionStore, viewMode: ChatViewMode) {
    ConversationFollowDebug.log(
      "ConversationViewModel.bind sessionId=\(sessionId ?? "nil") endpointId=\(sessionStore.endpointId.uuidString) viewMode=\(String(describing: viewMode))"
    )
    currentSessionId = sessionId
    currentSessionStore = sessionStore
    currentViewMode = viewMode
    timelineViewModel.bind(sessionId: sessionId)
    sessionObservationGeneration &+= 1
    startObservation(generation: sessionObservationGeneration)
  }

  func handleTimelineViewModeChange(_ viewMode: ChatViewMode) {
    ConversationFollowDebug.log(
      "ConversationViewModel.handleTimelineViewModeChange old=\(String(describing: currentViewMode)) new=\(String(describing: viewMode))"
    )
    currentViewMode = viewMode
    guard let timeline else { return }
    timelineViewModel.apply(presentation: timeline, viewMode: viewMode)
  }

  func handleLoadStateChange(_ newState: ConversationLoadState) {
    ConversationFollowDebug.log("ConversationViewModel.handleLoadStateChange newState=\(String(describing: newState))")
    if newState == .ready {
      hasShownContent = true
    }
  }

  func loadOlderMessages() {
    guard let currentSessionId else { return }
    ConversationFollowDebug.log(
      "ConversationViewModel.loadOlderMessages sessionId=\(currentSessionId) limit=\(pageSize)"
    )
    currentSessionStore.loadOlderMessages(sessionId: currentSessionId, limit: pageSize)
  }

  private func startObservation(generation: UInt64) {
    guard let currentSessionId else {
      apply(snapshot: .empty)
      return
    }

    let sessionStore = currentSessionStore

    // Read the snapshot inside the tracking block so observation is registered
    // for changes to the authoritative SessionObservable. Apply it OUTSIDE so
    // that writes to self-properties (timeline, loadState, etc.) don't consume
    // the one-shot onChange before the tracked property can trigger it.
    let snapshot = withObservationTracking {
      Self.buildSnapshot(session: sessionStore.session(currentSessionId), sessionStore: sessionStore)
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.sessionObservationGeneration == generation else { return }
        self.startObservation(generation: generation)
      }
    }

    apply(snapshot: snapshot)
  }

  private func apply(snapshot: ConversationSnapshot) {
    let previousEntries = timeline?.entries ?? []
    let nextLoadState: ConversationLoadState = if let timeline = snapshot.timeline, !timeline.entries.isEmpty {
      .ready
    } else if hasShownContent || snapshot.conversationLoaded {
      .empty
    } else {
      .loading
    }
    timeline = snapshot.timeline
    if let timeline = snapshot.timeline {
      timelineViewModel.apply(presentation: timeline, viewMode: currentViewMode)
      let appendedCount = ConversationTimelineDeltaPlanner.latestAppendedCount(
        oldEntries: previousEntries,
        newEntries: timeline.entries
      )
      if appendedCount > 0 {
        latestAppendEvent = ConversationLatestAppendEvent(
          count: appendedCount,
          nonce: (latestAppendEvent?.nonce ?? 0) + 1
        )
      }
      ConversationFollowDebug.log(
        """
        ConversationViewModel.applySnapshot sessionId=\(currentSessionId ?? "nil") oldCount=\(previousEntries
          .count) newCount=\(timeline.entries
          .count) appendedCount=\(appendedCount) loadState=\(String(
          describing: nextLoadState
        )) hasShownContent=\(hasShownContent)
        """
      )
    } else {
      ConversationFollowDebug.log(
        "ConversationViewModel.applySnapshot clearedTimeline sessionId=\(currentSessionId ?? "nil") loadState=\(String(describing: nextLoadState))"
      )
      timelineViewModel.clearSession()
    }
    loadState = nextLoadState
    forkOrigin = snapshot.forkOrigin
  }

  private static func buildSnapshot(
    session: SessionObservable,
    sessionStore: SessionStore
  ) -> ConversationSnapshot {
    let timeline = ConversationTimelinePresentation(
      entries: session.rowEntries,
      contentRevision: session.rowEntriesContentRevision,
      structureRevision: session.rowEntriesStructureRevision,
      changedEntries: session.lastChangedRowEntries
    )

    let forkOrigin: ConversationForkOriginPresentation? = if let sourceId = session.forkedFrom {
      ConversationForkOriginPresentation(
        sourceSessionId: sourceId,
        sourceEndpointId: sessionStore.endpointId,
        sourceName: sessionStore.session(sourceId).displayName
      )
    } else {
      nil
    }

    return ConversationSnapshot(
      timeline: timeline,
      conversationLoaded: session.conversationLoaded,
      forkOrigin: forkOrigin
    )
  }
}

struct ConversationSnapshot {
  let timeline: ConversationTimelinePresentation?
  let conversationLoaded: Bool
  let forkOrigin: ConversationForkOriginPresentation?

  static let empty = ConversationSnapshot(
    timeline: nil,
    conversationLoaded: false,
    forkOrigin: nil
  )
}

struct ConversationForkOriginPresentation {
  let sourceSessionId: String
  let sourceEndpointId: UUID?
  let sourceName: String?
}

struct ConversationTimelinePresentation {
  let entries: [ServerConversationRowEntry]
  let contentRevision: Int
  let structureRevision: Int
  let changedEntries: [ServerConversationRowEntry]
}
