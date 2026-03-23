import SwiftUI

struct MissionAgentCard: View {
  let issue: MissionIssueItem
  let conversation: DashboardConversationRecord?
  let isCompact: Bool
  let onNavigateToSession: (String) -> Void
  let onEndSession: ((String) async -> Void)?
  @Binding var expandedIssueId: String?

  private var isExpanded: Bool {
    expandedIssueId == issue.issueId
  }

  private var cardAccent: Color {
    conversation?.displayStatus.color ?? issue.orchestrationState.color
  }

  private var needsUrgentGlow: Bool {
    conversation?.displayStatus == .permission || conversation?.displayStatus == .question
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // ── Row 1: Identifier + elapsed ──
      HStack(alignment: .firstTextBaseline) {
        Text(issue.identifier)
          .font(.system(size: TypeScale.caption, weight: .bold, design: .monospaced))
          .foregroundStyle(Color.accent)

        Spacer()

        if let conversation {
          TimelineView(.periodic(from: .now, by: 1.0)) { context in
            if let startedAt = conversation.startedAt {
              let elapsed = context.date.timeIntervalSince(startedAt)
              if elapsed > 0 {
                Text(DashboardFormatters.formatDuration(elapsed))
                  .font(.system(size: TypeScale.micro, weight: .medium, design: .monospaced))
                  .foregroundStyle(Color.textQuaternary)
              }
            }
          }
        }
      }

      // ── Row 2: Title ──
      Text(issue.title)
        .font(.system(size: TypeScale.caption))
        .foregroundStyle(Color.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(isExpanded ? nil : 2)

      // ── Row 3: Status + provider + model ──
      HStack(spacing: Spacing.sm_) {
        if let conversation {
          SessionStatusBadge(status: conversation.displayStatus, showIcon: true, size: .compact)
        } else {
          Text(issue.orchestrationState.displayLabel)
            .font(.system(size: TypeScale.micro, weight: .semibold))
            .foregroundStyle(issue.orchestrationState.color)
        }

        Spacer()

        Text(issue.provider.capitalized)
          .font(.system(size: TypeScale.micro, weight: .semibold))
          .foregroundStyle(issue.providerColor)

        if let conversation {
          UnifiedModelBadge(model: conversation.model, provider: conversation.provider, size: .mini)
        }
      }

      // ── Row 4: Activity — the hero content ──
      activityContent

      // ── Expanded detail ──
      if isExpanded {
        expandedContent
      }

      // ── Row 5: Footer — branch + metrics + actions ──
      footer
    }
    .padding(.leading, Spacing.md)
    .padding(.trailing, Spacing.md)
    .padding(.vertical, Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(Motion.standard) {
        expandedIssueId = isExpanded ? nil : issue.issueId
      }
    }
  }

  // MARK: - Activity Content (Hero)

  @ViewBuilder
  private var activityContent: some View {
    if let conversation, conversation.displayStatus == .permission, let tool = conversation.pendingToolName {
      // Permission request — urgent, prominent
      HStack(spacing: Spacing.sm_) {
        Image(systemName: "lock.fill")
          .font(.system(size: IconScale.sm, weight: .bold))
        Text(tool)
          .lineLimit(1)
      }
      .font(.system(size: TypeScale.caption, weight: .medium))
      .foregroundStyle(Color.statusPermission)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color.statusPermission.opacity(OpacityTier.subtle),
        in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
      )
    } else if let conversation, conversation.displayStatus == .question {
      // Question — urgent, prominent
      HStack(spacing: Spacing.sm_) {
        Image(systemName: "questionmark.bubble")
          .font(.system(size: IconScale.sm, weight: .bold))
        Text(conversation.pendingQuestion.map { String($0.prefix(80)) } ?? "Question")
          .lineLimit(2)
      }
      .font(.system(size: TypeScale.caption, weight: .medium))
      .foregroundStyle(Color.statusQuestion)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color.statusQuestion.opacity(OpacityTier.subtle),
        in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
      )
    } else if let tool = conversation?.pendingToolName {
      // Active tool use
      HStack(spacing: Spacing.sm_) {
        Image(systemName: "wrench.fill")
          .font(.system(size: IconScale.xs, weight: .medium))
        Text(tool)
          .lineLimit(1)
      }
      .font(.system(size: TypeScale.micro, weight: .medium))
      .foregroundStyle(Color.textSecondary)
    } else if let contextLine = conversation?.contextLine, !contextLine.isEmpty {
      // Context line (assistant output)
      HStack(spacing: Spacing.sm_) {
        Image(systemName: "text.bubble")
          .font(.system(size: IconScale.xs, weight: .medium))
        Text(contextLine)
          .lineLimit(2)
      }
      .font(.system(size: TypeScale.micro, weight: .medium))
      .foregroundStyle(Color.textSecondary)
    } else if conversation != nil {
      HStack(spacing: Spacing.sm_) {
        Image(systemName: "brain")
          .font(.system(size: IconScale.xs, weight: .medium))
        Text("Thinking...")
      }
      .font(.system(size: TypeScale.micro, weight: .medium))
      .foregroundStyle(Color.textTertiary)
    } else {
      HStack(spacing: Spacing.sm_) {
        ProgressView()
          .controlSize(.mini)
        Text("Initializing...")
      }
      .font(.system(size: TypeScale.micro, weight: .medium))
      .foregroundStyle(Color.textQuaternary)
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: Spacing.sm) {
      // Branch badge
      if let branch = conversation?.branch {
        HStack(spacing: Spacing.xxs) {
          Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 8, weight: .medium))
          Text(branch)
            .lineLimit(1)
        }
        .font(.system(size: TypeScale.micro, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.textQuaternary)
      }

      // Inline metrics
      if let conversation {
        if conversation.toolCount > 0 {
          metricPill(icon: "wrench.fill", value: "\(conversation.toolCount)")
        }
        if conversation.hasTurnDiff {
          metricPill(icon: "doc.badge.plus", value: "diff")
        }
        if conversation.activeWorkerCount > 0 {
          metricPill(icon: "person.2.fill", value: "\(conversation.activeWorkerCount)")
        }
      }

      Spacer()

      if let sessionId = issue.sessionId {
        Button {
          Task { await onEndSession?(sessionId) }
        } label: {
          Image(systemName: "stop.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.feedbackNegative)
            .frame(width: 22, height: 22)
            .background(
              Color.feedbackNegative.opacity(OpacityTier.subtle),
              in: RoundedRectangle(cornerRadius: Radius.sm_, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help("Stop agent")

        Button {
          onNavigateToSession(sessionId)
        } label: {
          Text("Open \u{2192}")
            .font(.system(size: TypeScale.micro, weight: .semibold))
            .foregroundStyle(Color.accent)
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - Expanded Content

  @ViewBuilder
  private var expandedContent: some View {
    VStack(alignment: .leading, spacing: Spacing.sm_) {
      Divider().foregroundStyle(Color.surfaceBorder)

      if let summary = expandedSummaryText {
        Text(summary)
          .font(.system(size: TypeScale.micro))
          .foregroundStyle(Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(Spacing.sm)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            Color.backgroundTertiary,
            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
          )
      } else {
        Text("Session context loading...")
          .font(.system(size: TypeScale.micro))
          .foregroundStyle(Color.textQuaternary)
      }

      if let conversation, let lastMessage = conversation.lastMessage, !lastMessage.isEmpty {
        Text(lastMessage)
          .font(.system(size: TypeScale.micro).italic())
          .foregroundStyle(Color.textTertiary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: - Card Background

  private var cardBackground: some View {
    ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: Radius.ml, style: .continuous)
        .fill(Color.backgroundSecondary)
        .overlay(
          RoundedRectangle(cornerRadius: Radius.ml, style: .continuous)
            .strokeBorder(
              needsUrgentGlow
                ? cardAccent.opacity(OpacityTier.medium)
                : Color.surfaceBorder.opacity(OpacityTier.subtle),
              lineWidth: needsUrgentGlow ? 1.5 : 0.5
            )
        )
        .shadow(
          color: needsUrgentGlow
            ? cardAccent.opacity(OpacityTier.light)
            : cardAccent.opacity(OpacityTier.subtle),
          radius: needsUrgentGlow ? 10 : 4,
          y: 2
        )

      // Left edge accent
      UnevenRoundedRectangle(
        topLeadingRadius: Radius.ml,
        bottomLeadingRadius: Radius.ml,
        bottomTrailingRadius: 0,
        topTrailingRadius: 0
      )
      .fill(cardAccent)
      .frame(width: EdgeBar.width)
    }
  }

  // MARK: - Helpers

  private func metricPill(icon: String, value: String) -> some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: icon)
        .font(.system(size: 7, weight: .bold))
      Text(value)
        .font(.system(size: TypeScale.micro, weight: .medium, design: .monospaced))
    }
    .foregroundStyle(Color.textQuaternary)
    .padding(.horizontal, Spacing.xs)
    .padding(.vertical, Spacing.xxs)
    .background(
      Color.backgroundTertiary.opacity(0.6),
      in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
    )
  }

  private var expandedSummaryText: String? {
    if let question = conversation?.pendingQuestion, !question.isEmpty {
      return question
    }
    if let toolName = conversation?.pendingToolName, !toolName.isEmpty {
      if let toolInput = conversation?.pendingToolInput, !toolInput.isEmpty {
        return "\(toolName): \(toolInput)"
      }
      return "Pending tool: \(toolName)"
    }
    if let contextLine = conversation?.contextLine, !contextLine.isEmpty {
      return contextLine
    }
    if let lastMessage = conversation?.lastMessage, !lastMessage.isEmpty {
      return lastMessage
    }
    return nil
  }
}
