//
//  TimelineScrollView.swift
//  OrbitDock
//
//  Pure SwiftUI replacement for NSTableView/UICollectionView timeline.
//  Heights are automatic — no manual measurement or caching needed.
//
//  Follow (pin-to-bottom) logic:
//  - Follow state is owned locally as @State so the scroll position binding
//    only reads same-view state — no cross-frame race with parent props.
//  - When pinned, the bound position stays on the bottom sentinel so container
//    height and content height changes preserve bottom alignment declaratively.
//  - User-driven scrolling is detected by bridging the underlying platform
//    scroll view so content/layout changes do not masquerade as user intent.
//  - The parent is notified of follow state changes via onFollowStateChanged
//    and sends commands (jump to latest, toggle, reveal) via scrollCommand.
//

import SwiftUI

struct TimelineScrollView: View {
  let viewModel: ConversationTimelineViewModel
  let sessionId: String
  let clients: ServerClients
  @Binding var scrollCommand: ConversationScrollCommand?
  let onLoadMore: (() -> Void)?
  let latestAppendEvent: ConversationLatestAppendEvent?
  let onFollowStateChanged: (ConversationFollowState) -> Void

  private static let bottomSentinelID = "timeline-bottom"
  private static let bottomAnchorHeight: CGFloat = 20
  private static let bottomThreshold: CGFloat = 36

  @State private var localFollowState = ConversationFollowState.initial
  @State private var isNearBottom = true
  @State private var commandedScrollPositionID: String? = bottomSentinelID
  @State private var observedScrollPositionID: String? = bottomSentinelID
  @State private var hasInitializedScrollPosition = false
  @State private var isUserScrolling = false
  @State private var hasDetachedFromBottomDuringCurrentGesture = false

  var body: some View {
    let displayed = viewModel.displayedEntries

    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(spacing: 0) {
          // Pagination sentinel — triggers history load when scrolled into view.
          // Identity changes when older messages prepend (first entry's sequence
          // changes), so onAppear fires again for the next page.
          Color.clear
            .frame(height: 1)
            .id("pagination-\(displayed.first?.sequence ?? 0)")
            .onAppear {
              guard hasInitializedScrollPosition, !localFollowState.mode.isFollowing else { return }
              onLoadMore?()
            }

          ForEach(displayed) { entry in
            TimelineRowHost(
              entry: entry,
              sessionId: sessionId,
              clients: clients,
              viewModel: viewModel
            )
            .id(entry.id)
          }

          // Bottom sentinel — padded docking region used only as the follow target.
          Color.clear
            .frame(height: Self.bottomAnchorHeight)
            .id(Self.bottomSentinelID)
        }
        .scrollTargetLayout()
        .background {
          TimelineUserScrollDetector(
            isUserScrolling: $isUserScrolling,
            isNearBottom: $isNearBottom,
            bottomThreshold: Self.bottomThreshold
          )
          .frame(width: 0, height: 0)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .defaultScrollAnchor(.bottom)
      .scrollPosition(id: scrollPositionBinding, anchor: .bottom)
      .background(Color.backgroundPrimary)
      .task {
        guard !hasInitializedScrollPosition else { return }
        hasInitializedScrollPosition = true
        ConversationFollowDebug.log(
          "TimelineScrollView.task initialize followMode=\(localFollowState.mode.rawValue) displayedCount=\(displayed.count) isNearBottom=\(isNearBottom)"
        )
        if localFollowState.mode.isFollowing {
          setPinnedScrollPosition()
        }
      }
      .onChange(of: isNearBottom) { _, isVisible in
        ConversationFollowDebug.log(
          "TimelineScrollView.nearBottomChanged isNearBottom=\(isVisible) followMode=\(localFollowState.mode.rawValue) isUserScrolling=\(isUserScrolling) commanded=\(commandedScrollPositionID ?? "nil") observed=\(observedScrollPositionID ?? "nil")"
        )
        if isVisible, !localFollowState.mode.isFollowing {
          ConversationFollowDebug.log("TimelineScrollView.applyIntent reachedBottom via metrics")
          applyIntent(.viewportEvent(.reachedBottom))
          return
        }

        guard !isVisible, localFollowState.mode.isFollowing, isUserScrolling else { return }
        guard !hasDetachedFromBottomDuringCurrentGesture else { return }
        ConversationFollowDebug.log("TimelineScrollView.applyIntent leftBottomByUser via metrics")
        hasDetachedFromBottomDuringCurrentGesture = true
        applyIntent(.viewportEvent(.leftBottomByUser))
      }
      .onChange(of: isUserScrolling) { _, scrolling in
        ConversationFollowDebug.log(
          "TimelineScrollView.userScrollingChanged scrolling=\(scrolling) followMode=\(localFollowState.mode.rawValue) isNearBottom=\(isNearBottom)"
        )
        if scrolling {
          hasDetachedFromBottomDuringCurrentGesture = false
          return
        }

        guard !hasDetachedFromBottomDuringCurrentGesture else { return }
        guard localFollowState.mode.isFollowing, !isNearBottom else { return }
        ConversationFollowDebug.log("TimelineScrollView.applyIntent leftBottomByUser via scroll end")
        hasDetachedFromBottomDuringCurrentGesture = true
        applyIntent(.viewportEvent(.leftBottomByUser))
      }
      .onChange(of: latestAppendEvent) { _, event in
        guard let event else { return }
        ConversationFollowDebug.log(
          "TimelineScrollView.latestAppendEvent count=\(event.count) nonce=\(event.nonce) followMode=\(localFollowState.mode.rawValue) unread=\(localFollowState.unreadCount)"
        )
        applyIntent(.latestEntriesAppended(event.count))
      }
      .onChange(of: scrollCommand) { _, command in
        guard let command else { return }
        ConversationFollowDebug.log(
          "TimelineScrollView.scrollCommandReceived command=\(describe(command)) followMode=\(localFollowState.mode.rawValue) isNearBottom=\(isNearBottom) displayedCount=\(displayed.count) commanded=\(commandedScrollPositionID ?? "nil") observed=\(observedScrollPositionID ?? "nil")"
        )
        run(command: command, with: proxy)
      }
    }
  }

  // MARK: - Follow Intent Processing

  private func applyIntent(_ intent: ConversationFollowIntent) {
    let plan = ConversationFollowPlanner.apply(current: localFollowState, intent: intent)
    localFollowState = plan.state
    onFollowStateChanged(plan.state)

    guard let action = plan.scrollAction else { return }
    switch action {
      case .latest:
        setPinnedScrollPosition()
      case .message:
        // Message scrolling requires ScrollViewProxy — handled via scrollCommand path
        break
    }
  }

  // MARK: - Scroll Actions

  private func setPinnedScrollPosition() {
    ConversationFollowDebug.log(
      "TimelineScrollView.setPinnedScrollPosition oldCommanded=\(commandedScrollPositionID ?? "nil") oldObserved=\(observedScrollPositionID ?? "nil") target=\(Self.bottomSentinelID)"
    )
    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
      commandedScrollPositionID = Self.bottomSentinelID
    }
  }

  private func scrollToMessage(_ messageID: String, with proxy: ScrollViewProxy) {
    ConversationFollowDebug.log("TimelineScrollView.scrollToMessage messageID=\(messageID)")
    var transaction = Transaction()
    transaction.animation = Motion.standard
    withTransaction(transaction) {
      proxy.scrollTo(messageID, anchor: .center)
    }
  }

  private func run(command: ConversationScrollCommand, with proxy: ScrollViewProxy) {
    ConversationFollowDebug.log("TimelineScrollView.run command=\(describe(command))")
    switch command {
      case .latest:
        setPinnedScrollPosition()
      case let .message(id, _):
        scrollToMessage(id, with: proxy)
      case .jumpToLatest:
        applyIntent(.jumpToLatest)
      case let .revealMessage(id, _):
        applyIntent(.revealMessage(id))
        scrollToMessage(id, with: proxy)
      case .toggleFollow:
        applyIntent(.toggleFollow)
      case .openPendingApproval:
        applyIntent(.openPendingApprovalPanel)
    }
  }

  // MARK: - Scroll Position Binding

  private var scrollPositionBinding: Binding<String?> {
    Binding(
      get: {
        // All reads are local @State — no cross-frame race with parent props.
        // When following: return the commanded position (bottom sentinel) to
        // pin the viewport to the bottom.
        // When detached: return nil so .scrollPosition does not fight the
        // user's scroll offset. Without this, the .bottom anchor tries to
        // reposition the viewport every layout pass (e.g. when new content
        // arrives), causing visible jank.
        if localFollowState.mode.isFollowing, !isUserScrolling {
          return commandedScrollPositionID ?? Self.bottomSentinelID
        }
        return nil
      },
      set: { newValue in
        observedScrollPositionID = newValue
      }
    )
  }

  private func describe(_ command: ConversationScrollCommand) -> String {
    switch command {
      case let .latest(nonce):
        "latest(nonce: \(nonce))"
      case let .message(id, nonce):
        "message(id: \(id), nonce: \(nonce))"
      case let .jumpToLatest(nonce):
        "jumpToLatest(nonce: \(nonce))"
      case let .revealMessage(id, nonce):
        "revealMessage(id: \(id), nonce: \(nonce))"
      case let .toggleFollow(nonce):
        "toggleFollow(nonce: \(nonce))"
      case let .openPendingApproval(nonce):
        "openPendingApproval(nonce: \(nonce))"
    }
  }
}

private struct TimelineRowHost: View {
  let entry: ServerConversationRowEntry
  let sessionId: String
  let clients: ServerClients
  let viewModel: ConversationTimelineViewModel

  private var expandableId: String? {
    switch entry.row {
      case let .tool(toolRow):
        toolRow.id
      case let .activityGroup(group):
        group.id
      default:
        nil
    }
  }

  private var fetchId: String? {
    switch entry.row {
      case let .tool(toolRow):
        toolRow.id
      case let .activityGroup(group):
        group.id
      default:
        nil
    }
  }

  private var isExpanded: Bool {
    expandableId.map { viewModel.isExpanded($0) } ?? false
  }

  private var isUndone: Bool {
    entry.turnStatus == .undone || entry.turnStatus == .rolledBack
  }

  var body: some View {
    TimelineRowContent(
      entry: entry,
      isExpanded: isExpanded,
      sessionId: sessionId,
      clients: clients,
      fetchedContent: fetchId.flatMap { viewModel.content(for: $0) },
      isLoadingContent: fetchId.map { viewModel.isFetching($0) } ?? false,
      onToggle: toggle,
      isItemExpanded: viewModel.isExpanded(_:),
      contentForChild: viewModel.content(for:),
      isChildLoading: viewModel.isFetching(_:)
    )
    .opacity(isUndone ? OpacityTier.strong : 1.0)
    .overlay(alignment: .topTrailing) {
      if isUndone {
        UndoneRowBadge(status: entry.turnStatus)
      }
    }
    .task(id: isExpanded) {
      guard isExpanded, let fetchId else { return }
      viewModel.fetchContentIfNeeded(rowId: fetchId, sessionId: sessionId, clients: clients)
      if case let .activityGroup(group) = entry.row {
        for child in group.children where viewModel.isExpanded(child.id) {
          viewModel.fetchContentIfNeeded(rowId: child.id, sessionId: sessionId, clients: clients)
        }
      }
    }
  }

  private func toggle(_ id: String) {
    let nowExpanded = viewModel.toggleExpanded(id)
    if nowExpanded {
      viewModel.fetchContentIfNeeded(rowId: id, sessionId: sessionId, clients: clients)
    }
  }
}

private struct UndoneRowBadge: View {
  let status: TurnStatus

  private var label: String {
    status == .undone ? "Undone" : "Rolled back"
  }

  var body: some View {
    Text(label)
      .font(.caption2)
      .fontWeight(.medium)
      .foregroundStyle(Color.textTertiary)
      .padding(.horizontal, Spacing.sm_)
      .padding(.vertical, Spacing.xxs)
      .background(Color.backgroundTertiary, in: Capsule())
      .padding(.trailing, Spacing.lg)
      .padding(.top, Spacing.xs)
  }
}
