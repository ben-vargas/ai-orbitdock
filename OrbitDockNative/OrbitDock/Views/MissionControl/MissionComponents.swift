import SwiftUI

// MARK: - Section Urgency

enum MissionSectionUrgency {
  case normal
  case attention
  case settled
}

// MARK: - Section Header

struct MissionSectionHeader: View {
  let title: String
  let icon: String
  var color: Color = .accent
  var count: Int?
  var trailing: String?
  var urgency: MissionSectionUrgency = .normal

  var body: some View {
    HStack(spacing: Spacing.sm_) {
      Image(systemName: icon)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(iconColor)

      Text(title)
        .font(.system(size: TypeScale.caption, weight: .bold, design: .monospaced))
        .foregroundStyle(titleColor)
        .tracking(0.3)

      if let count {
        Text("\(count)")
          .font(.system(size: TypeScale.micro, weight: .bold, design: .monospaced))
          .foregroundStyle(countColor)
          .padding(.horizontal, Spacing.xs)
          .padding(.vertical, 1)
          .background(
            countColor.opacity(OpacityTier.subtle),
            in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
          )
      }

      Spacer()

      if let trailing {
        Text(trailing)
          .font(.system(size: TypeScale.micro, weight: .bold, design: .monospaced))
          .foregroundStyle(Color.textTertiary)
      }
    }
  }

  private var iconColor: Color {
    switch urgency {
      case .normal: color
      case .attention: color
      case .settled: Color.textQuaternary
    }
  }

  private var titleColor: Color {
    switch urgency {
      case .normal: Color.textPrimary
      case .attention: Color.textPrimary
      case .settled: Color.textTertiary
    }
  }

  private var countColor: Color {
    switch urgency {
      case .normal: color
      case .attention: Color.feedbackNegative
      case .settled: color
    }
  }
}

// MARK: - Stat Chip

enum MissionStatChipStyle {
  case dot
  case icon(String)
}

struct MissionStatChip: View {
  let count: UInt32
  let label: String
  let color: Color
  var style: MissionStatChipStyle = .dot

  var body: some View {
    HStack(spacing: Spacing.xs) {
      switch style {
        case .dot:
          Circle()
            .fill(color)
            .frame(width: 5, height: 5)
        case let .icon(name):
          Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(count > 0 ? color : Color.textQuaternary)
      }

      Text("\(count)")
        .font(.system(size: TypeScale.caption, weight: .bold, design: .monospaced))
        .foregroundStyle(count > 0 ? color : Color.textQuaternary)

      Text(label)
        .font(.system(size: TypeScale.micro, weight: .medium))
        .foregroundStyle(Color.textTertiary)
    }
  }
}

// MARK: - Issue Transition Menu

/// Server-driven action menu for issue state transitions.
/// Renders only the transitions the server says are valid.
struct IssueTransitionMenu: View {
  let issue: MissionIssueItem
  let onTransition: (OrchestrationState, String?) async -> Void

  var body: some View {
    if !issue.allowedTransitions.isEmpty {
      Menu {
        ForEach(issue.allowedTransitions, id: \.self) { target in
          Button {
            Task { await onTransition(target, nil) }
          } label: {
            Label(target.transitionLabel, systemImage: target.transitionIcon)
          }
        }

        if issue.sessionId != nil {
          Divider()
        }

        if let urlString = issue.url, let url = URL(string: urlString) {
          Button {
            _ = Platform.services.openURL(url)
          } label: {
            Label("Open in Tracker", systemImage: "arrow.up.right.square")
          }
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(Color.textTertiary)
          .frame(width: 24, height: 24)
          .background(
            Color.backgroundTertiary.opacity(0.6),
            in: RoundedRectangle(cornerRadius: Radius.sm_, style: .continuous)
          )
      }
      .buttonStyle(.plain)
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
  }
}

// MARK: - Issue Filtering

extension [MissionIssueItem] {
  var running: [MissionIssueItem] {
    filter { $0.orchestrationState == .running || $0.orchestrationState == .claimed }
  }

  var queued: [MissionIssueItem] {
    filter { $0.orchestrationState == .queued || $0.orchestrationState == .retryQueued }
  }

  var completed: [MissionIssueItem] {
    filter { $0.orchestrationState == .completed }
  }

  var failed: [MissionIssueItem] {
    filter { $0.orchestrationState == .failed }
  }

  var blocked: [MissionIssueItem] {
    filter { $0.orchestrationState == .blocked }
  }
}
