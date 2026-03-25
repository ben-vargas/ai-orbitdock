//
//  ConversationView.swift
//  OrbitDock
//

import SwiftUI

struct ConversationView: View {
  let sessionId: String?
  let sessionStore: SessionStore
  var endpointId: UUID?
  var isSessionActive: Bool = false
  var displayStatus: SessionDisplayStatus = .ended
  var currentTool: String?
  var chatViewMode: ChatViewMode = .focused
  @Binding var scrollCommand: ConversationScrollCommand?

  let followMode: ConversationFollowMode
  let unreadCount: Int
  let onJumpToLatest: () -> Void
  let onViewportEvent: (ConversationViewportEvent) -> Void
  let onLatestEntriesAppended: (_ count: Int) -> Void
  @State private var viewModel = ConversationViewModel()

  var body: some View {
    ZStack {
      Color.backgroundPrimary
        .ignoresSafeArea()

      switch viewModel.loadState {
        case .loading:
          ConversationLoadingView()
            .transition(.opacity)
        case .empty:
          ConversationEmptyStateView()
            .transition(.opacity)
        case .ready:
          VStack(spacing: 0) {
            if let forkOrigin = viewModel.forkOrigin {
              ConversationForkOriginBanner(
                sourceSessionId: forkOrigin.sourceSessionId,
                sourceEndpointId: forkOrigin.sourceEndpointId ?? endpointId,
                sourceName: forkOrigin.sourceName
              )
              .padding(.horizontal, Spacing.lg)
              .padding(.top, Spacing.sm)
              .padding(.bottom, Spacing.xs)
            }

            ZStack(alignment: .bottomTrailing) {
              conversationTimeline

              if !followMode.isFollowing {
                ConversationFollowPill(
                  unreadCount: unreadCount,
                  onTap: onJumpToLatest
                )
                .padding(.trailing, Spacing.lg)
                .padding(.bottom, Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(Motion.standard, value: followMode)
              }
            }

            if isSessionActive || displayStatus == .ended {
              OrbitStatusIndicator(
                displayStatus: displayStatus,
                currentTool: currentTool
              )
            }
          }
          .transition(.opacity)
      }
    }
    .task(id: "\(sessionStore.endpointId.uuidString):\(sessionId ?? "")") {
      ConversationFollowDebug.log(
        "ConversationView.task bind sessionId=\(sessionId ?? "nil") endpointId=\(sessionStore.endpointId.uuidString) followMode=\(followMode.rawValue) unread=\(unreadCount)"
      )
      viewModel.bind(sessionId: sessionId, sessionStore: sessionStore, viewMode: chatViewMode)
    }
    .animation(Motion.fade, value: viewModel.loadState == .loading)
    .onChange(of: viewModel.loadState) { _, newState in
      ConversationFollowDebug.log("ConversationView.loadStateChanged newState=\(String(describing: newState))")
      viewModel.handleLoadStateChange(newState)
    }
    .onChange(of: viewModel.latestAppendEvent) { _, event in
      guard let event else { return }
      ConversationFollowDebug.log(
        "ConversationView.latestAppendEvent count=\(event.count) nonce=\(event.nonce) followMode=\(followMode.rawValue) unread=\(unreadCount)"
      )
      onLatestEntriesAppended(event.count)
    }
    .onChange(of: chatViewMode) { _, newMode in
      ConversationFollowDebug.log("ConversationView.chatViewModeChanged newMode=\(String(describing: newMode))")
      viewModel.handleTimelineViewModeChange(newMode)
    }
    .onChange(of: followMode) { oldMode, newMode in
      ConversationFollowDebug.log(
        "ConversationView.followModeChanged old=\(oldMode.rawValue) new=\(newMode.rawValue) unread=\(unreadCount)"
      )
    }
    .onChange(of: unreadCount) { oldCount, newCount in
      ConversationFollowDebug.log(
        "ConversationView.unreadChanged old=\(oldCount) new=\(newCount) followMode=\(followMode.rawValue)"
      )
    }
  }

  // MARK: - Timeline

  @ViewBuilder
  private var conversationTimeline: some View {
    if viewModel.timeline != nil, let sessionId {
      TimelineScrollView(
        viewModel: viewModel.timelineViewModel,
        sessionId: sessionId,
        clients: sessionStore.clients,
        scrollCommand: $scrollCommand,
        onLoadMore: {
          viewModel.loadOlderMessages()
        },
        followMode: followMode,
        onViewportEvent: onViewportEvent
      )
    } else {
      ConversationEmptyStateView()
    }
  }
}

/// Internal to ConversationView — declared at file scope for Equatable conformance
enum ConversationLoadState: Equatable {
  case loading, empty, ready
}

// MARK: - Preview

#Preview {
  @Previewable @State var followMode: ConversationFollowMode = .following
  @Previewable @State var unreadCount = 0
  @Previewable @State var scrollCommand: ConversationScrollCommand?

  ConversationView(
    sessionId: nil,
    sessionStore: SessionStore.preview(),
    isSessionActive: true,
    displayStatus: .working,
    currentTool: "Edit",
    scrollCommand: $scrollCommand,
    followMode: followMode,
    unreadCount: unreadCount,
    onJumpToLatest: {
      followMode = .following
      unreadCount = 0
    },
    onViewportEvent: { event in
      switch event {
        case .reachedBottom:
          followMode = .following
          unreadCount = 0
        case .leftBottomByUser:
          followMode = .detachedByUser
      }
    },
    onLatestEntriesAppended: { count in
      guard !followMode.isFollowing else { return }
      unreadCount += count
    }
  )
  .frame(width: 700, height: 600)
  .background(Color.backgroundPrimary)
}
