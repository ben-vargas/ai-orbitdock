import SwiftUI

struct NewSessionStageCard<Content: View>: View {
  let eyebrow: String?
  let title: String
  let subtitle: String?
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if let eyebrow {
          Text(eyebrow)
            .font(.system(size: TypeScale.micro, weight: .semibold))
            .foregroundStyle(Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
        }

        Text(title)
          .font(.system(size: TypeScale.subhead, weight: .semibold))
          .foregroundStyle(Color.textPrimary)

        if let subtitle {
          Text(subtitle)
            .font(.system(size: TypeScale.caption))
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      content()
    }
    .padding(Spacing.lg)
    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        .stroke(Color.surfaceBorder.opacity(OpacityTier.light), lineWidth: 1)
    )
  }
}

struct NewSessionSheetShell<Header: View, FormContent: View, Footer: View>: View {
  @ViewBuilder let header: () -> Header
  @ViewBuilder let formContent: () -> FormContent
  @ViewBuilder let footer: () -> Footer

  var body: some View {
    let chrome = VStack(spacing: 0) {
      header()

      divider

      formContent()

      divider

      footer()
    }
    .background(
      RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        .fill(Color.backgroundSecondary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        .stroke(Color.surfaceBorder.opacity(OpacityTier.light), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.32), radius: 28, y: 14)
    .shadow(color: Color.accent.opacity(0.08), radius: 18, y: 0)

    #if os(iOS)
      chrome
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    #else
      chrome
        .padding(Spacing.md)
        .frame(minWidth: 540, idealWidth: 620, maxWidth: 720)
    #endif
  }

  private var divider: some View {
    Rectangle()
      .fill(Color.surfaceBorder.opacity(OpacityTier.light))
      .frame(height: 1)
  }
}

struct NewSessionFormShell<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    #if os(iOS)
      ScrollView(showsIndicators: false) {
        content()
          .padding(.horizontal, Spacing.lg)
          .padding(.vertical, Spacing.lg)
          .padding(.bottom, Spacing.sm)
      }
    #else
      ScrollView(showsIndicators: true) {
        content()
          .padding(.horizontal, Spacing.lg)
          .padding(.vertical, Spacing.section)
      }
    #endif
  }
}

struct NewSessionFormSections<
  ProviderPicker: View,
  EndpointSection: View,
  ContinuationSection: View,
  AuthGateSection: View,
  CodexCapabilityNoticeSection: View,
  DirectorySection: View,
  WorktreeSection: View,
  ConfigurationCard: View,
  ToolRestrictionsCard: View,
  ErrorBanner: View
>: View {
  let formSectionSpacing: CGFloat
  let shouldShowEndpointSection: Bool
  let continuation: SessionContinuation?
  let isCodexProvider: Bool
  let isClaudeProvider: Bool
  let shouldShowAuthGate: Bool
  let shouldShowCodexCapabilityNotice: Bool
  let hasSelectedPath: Bool
  let hasCodexError: Bool
  @ViewBuilder let providerPicker: () -> ProviderPicker
  @ViewBuilder let endpointSection: () -> EndpointSection
  @ViewBuilder let continuationSection: (SessionContinuation) -> ContinuationSection
  @ViewBuilder let authGateSection: () -> AuthGateSection
  @ViewBuilder let codexCapabilityNoticeSection: () -> CodexCapabilityNoticeSection
  @ViewBuilder let directorySection: () -> DirectorySection
  @ViewBuilder let worktreeSection: () -> WorktreeSection
  @ViewBuilder let configurationCard: () -> ConfigurationCard
  @ViewBuilder let toolRestrictionsCard: () -> ToolRestrictionsCard
  @ViewBuilder let errorBanner: () -> ErrorBanner

  var body: some View {
    VStack(alignment: .leading, spacing: formSectionSpacing) {
      NewSessionStageCard(
        eyebrow: "Stage 1",
        title: "Session Setup",
        subtitle: "Choose the provider and where this session should run."
      ) {
        providerPicker()

        if shouldShowEndpointSection {
          Rectangle()
            .fill(Color.surfaceBorder.opacity(OpacityTier.light))
            .frame(height: 1)

          endpointSection()
        }
      }

      if let continuation {
        continuationSection(continuation)
      }

      if isCodexProvider, shouldShowAuthGate {
        authGateSection()
      }

      if isCodexProvider, shouldShowCodexCapabilityNotice {
        codexCapabilityNoticeSection()
      }

      NewSessionStageCard(
        eyebrow: "Stage 2",
        title: "Workspace",
        subtitle: hasSelectedPath
          ? "Confirm the directory, then decide whether this run should branch into a worktree."
          : "Pick a recent project or browse for the directory you want this session to use."
      ) {
        directorySection()

        if hasSelectedPath {
          Rectangle()
            .fill(Color.surfaceBorder.opacity(OpacityTier.light))
            .frame(height: 1)

          worktreeSection()
        }
      }

      configurationCard()

      if isClaudeProvider {
        toolRestrictionsCard()
      }

      if hasCodexError {
        errorBanner()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
