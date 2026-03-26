import SwiftUI

struct SetupSettingsView: View {
  let serverState: SessionStore
  @State private var model = SetupSettingsModel()

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.xl) {
        ClaudeHooksSetupPane(model: model)
        CodexAccountSetupPane(serverState: serverState)
      }
      .padding(Spacing.xl)
    }
    .task(id: serverState.endpointId) {
      model.refreshHooksConfiguration()
      serverState.refreshCodexAccount()
    }
  }
}
