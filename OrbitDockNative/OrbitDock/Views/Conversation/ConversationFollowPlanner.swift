import Foundation

enum ConversationFollowMode: String, Equatable, Sendable {
  case following
  case detachedByUser
  case programmaticNavigation

  var isFollowing: Bool {
    self == .following
  }

  var statusLabel: String {
    switch self {
      case .following:
        "Following"
      case .detachedByUser:
        "Paused"
      case .programmaticNavigation:
        "Browsing"
    }
  }

  var controlIcon: String {
    switch self {
      case .following:
        "arrow.down.to.line"
      case .detachedByUser:
        "pause"
      case .programmaticNavigation:
        "scope"
    }
  }
}

struct ConversationFollowState: Equatable, Sendable {
  var mode: ConversationFollowMode
  var unreadCount: Int

  static let initial = ConversationFollowState(mode: .following, unreadCount: 0)
}

enum ConversationViewportEvent: Equatable, Sendable {
  case reachedBottom
  case leftBottomByUser
}

enum ConversationScrollAction: Equatable, Sendable {
  case latest
  case message(String)
}

enum ConversationFollowIntent: Equatable, Sendable {
  case viewportEvent(ConversationViewportEvent)
  case latestEntriesAppended(Int)
  case jumpToLatest
  case toggleFollow
  case revealMessage(String)
  case openPendingApprovalPanel
}

struct ConversationFollowPlan: Equatable, Sendable {
  let state: ConversationFollowState
  let scrollAction: ConversationScrollAction?
}

enum ConversationFollowPlanner {
  static func apply(
    current: ConversationFollowState,
    intent: ConversationFollowIntent
  ) -> ConversationFollowPlan {
    let plan = switch intent {
      case let .viewportEvent(event):
        viewportPlan(current: current, event: event)
      case let .latestEntriesAppended(count):
        latestEntriesPlan(current: current, count: count)
      case .jumpToLatest:
        plan(
          current: current,
          mode: .following,
          unreadCount: 0,
          scrollAction: .latest
        )
      case .toggleFollow:
        togglePlan(current: current)
      case let .revealMessage(messageID):
        plan(
          current: current,
          mode: .programmaticNavigation,
          unreadCount: current.unreadCount,
          scrollAction: .message(messageID)
        )
      case .openPendingApprovalPanel:
        plan(
          current: current,
          mode: .following,
          unreadCount: 0,
          scrollAction: .latest
        )
    }
    ConversationFollowDebug.log(
      """
      ConversationFollowPlanner.apply intent=\(describe(intent)) oldMode=\(current.mode.rawValue) oldUnread=\(current
        .unreadCount) newMode=\(plan.state.mode.rawValue) newUnread=\(plan.state
        .unreadCount) scrollAction=\(describe(plan.scrollAction))
      """
    )
    return plan
  }

  private static func viewportPlan(
    current: ConversationFollowState,
    event: ConversationViewportEvent
  ) -> ConversationFollowPlan {
    switch event {
      case .reachedBottom:
        return plan(
          current: current,
          mode: .following,
          unreadCount: 0,
          scrollAction: nil
        )
      case .leftBottomByUser:
        guard current.mode != .detachedByUser else {
          return ConversationFollowPlan(state: current, scrollAction: nil)
        }
        return plan(
          current: current,
          mode: .detachedByUser,
          unreadCount: current.unreadCount,
          scrollAction: nil
        )
    }
  }

  private static func latestEntriesPlan(
    current: ConversationFollowState,
    count: Int
  ) -> ConversationFollowPlan {
    guard count > 0 else {
      return ConversationFollowPlan(state: current, scrollAction: nil)
    }
    guard !current.mode.isFollowing else {
      return ConversationFollowPlan(state: current, scrollAction: nil)
    }

    return plan(
      current: current,
      mode: current.mode,
      unreadCount: current.unreadCount + count,
      scrollAction: nil
    )
  }

  private static func togglePlan(current: ConversationFollowState) -> ConversationFollowPlan {
    if current.mode.isFollowing {
      return plan(
        current: current,
        mode: .detachedByUser,
        unreadCount: current.unreadCount,
        scrollAction: nil
      )
    }

    return plan(
      current: current,
      mode: .following,
      unreadCount: 0,
      scrollAction: .latest
    )
  }

  private static func plan(
    current _: ConversationFollowState,
    mode: ConversationFollowMode,
    unreadCount: Int,
    scrollAction: ConversationScrollAction?
  ) -> ConversationFollowPlan {
    ConversationFollowPlan(
      state: ConversationFollowState(mode: mode, unreadCount: unreadCount),
      scrollAction: scrollAction
    )
  }

  private static func describe(_ intent: ConversationFollowIntent) -> String {
    switch intent {
      case let .viewportEvent(event):
        "viewportEvent(\(describe(event)))"
      case let .latestEntriesAppended(count):
        "latestEntriesAppended(\(count))"
      case .jumpToLatest:
        "jumpToLatest"
      case .toggleFollow:
        "toggleFollow"
      case let .revealMessage(messageID):
        "revealMessage(\(messageID))"
      case .openPendingApprovalPanel:
        "openPendingApprovalPanel"
    }
  }

  private static func describe(_ action: ConversationScrollAction?) -> String {
    guard let action else { return "nil" }
    return switch action {
      case .latest:
        "latest"
      case let .message(messageID):
        "message(\(messageID))"
    }
  }

  private static func describe(_ event: ConversationViewportEvent) -> String {
    switch event {
      case .reachedBottom:
        "reachedBottom"
      case .leftBottomByUser:
        "leftBottomByUser"
    }
  }
}
