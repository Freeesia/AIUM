import SwiftUI
import UIKit

private struct BrowserDestination: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var browserDestination: BrowserDestination?

    var body: some View {
        NavigationStack {
            Form {
                // GitHub section
                Section {
                    if viewModel.isDemoMode {
                        demoModeAuthMessage
                    } else {
                        if !viewModel.isGitHubClientIdConfigured {
                            clientIdWarning
                        }
                        githubAuthRow
                        if viewModel.isGitHubAuthenticated {
                            limitRow(label: "AI Credit Limit", value: $viewModel.aiCreditMonthlyLimit,
                                     placeholder: "e.g. 1000")
                            limitRow(label: "Premium Request Limit", value: $viewModel.premiumRequestMonthlyLimit,
                                     placeholder: "e.g. 300")
                        }
                    }
                } header: {
                    Text("GitHub Copilot")
                } footer: {
                    if !viewModel.isDemoMode {
                        githubFooter
                    }
                }

                // Codex section
                Section {
                    if viewModel.isDemoMode {
                        demoModeAuthMessage
                    } else {
                        if !viewModel.isCodexClientIdConfigured {
                            codexClientIdWarning
                        }
                        codexAuthRow
                        if viewModel.isCodexAuthenticated,
                           let account = viewModel.codexAccountDisplayName {
                            HStack {
                                Text("Account")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(account)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                } header: {
                    Text("OpenAI Codex")
                }

                // Refresh interval
                Section {
                    Picker("Interval", selection: $viewModel.refreshSetting) {
                        ForEach(UsageRefreshSetting.allCases) { setting in
                            Text(setting.displayName).tag(setting)
                        }
                    }
                } header: {
                    Text("Refresh")
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                viewModel.checkAuthStatus()
            }
            .sheet(item: $browserDestination) { destination in
                SafariBrowserView(url: destination.url)
                    .ignoresSafeArea()
            }
            .onChange(of: viewModel.isGitHubAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    browserDestination = nil
                }
            }
            .onChange(of: viewModel.isCodexAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    browserDestination = nil
                }
            }
            .onChange(of: viewModel.authError) { _, authError in
                if authError != nil {
                    browserDestination = nil
                }
            }
            .alert("Auth Error", isPresented: .init(
                get: { viewModel.authError != nil },
                set: { if !$0 { viewModel.authError = nil } }
            )) {
                Button("OK") { viewModel.authError = nil }
            } message: {
                Text(viewModel.authError ?? "")
            }
        }
    }

    // MARK: - Demo mode message

    private var demoModeAuthMessage: some View {
        Text("Demo Mode is active. Sign-in is disabled while sample data is shown.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - GitHub auth row

    @ViewBuilder
    private var githubAuthRow: some View {
        if viewModel.isGitHubAuthenticated {
            HStack {
                Label("GitHub", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Sign Out", role: .destructive) {
                    viewModel.logoutGitHub()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if viewModel.isAuthenticatingGitHub {
            if let code = viewModel.githubUserCode {
                deviceCodePrompt(userCode: code, url: viewModel.githubVerificationURL ?? "")
            } else {
                ProgressView("Connecting to GitHub…")
            }
        } else {
            Button {
                viewModel.startGitHubLogin()
            } label: {
                Label("Sign in with GitHub", systemImage: "person.badge.plus")
            }
            .disabled(!viewModel.isGitHubClientIdConfigured)
        }
    }

    private var clientIdWarning: some View {
        Label {
            Text("Set GITHUB_OAUTH_CLIENT_ID in the AIUM target build settings before signing in.")
                .font(.caption)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var githubFooter: some View {
        Text("GitHub opens with the device code copied. The configured GitHub App requests read-only access to your billing plan. Set monthly limits manually because the usage report does not return your plan allowance.")
    }

    // MARK: - Codex auth row

    @ViewBuilder
    private var codexAuthRow: some View {
        if viewModel.isCodexAuthenticated {
            HStack {
                Label("Codex", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Sign Out", role: .destructive) {
                    viewModel.logoutCodex()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if viewModel.isAuthenticatingCodex {
            if let code = viewModel.codexUserCode {
                deviceCodePrompt(userCode: code, url: viewModel.codexVerificationURL ?? "")
            } else {
                ProgressView("Connecting to Codex…")
            }
        } else {
            Button {
                viewModel.startCodexLogin()
            } label: {
                Label("Sign in with Codex", systemImage: "person.badge.plus")
            }
            .disabled(!viewModel.isCodexClientIdConfigured)
        }
    }

    private var codexClientIdWarning: some View {
        Label {
            Text("Set CODEX_OAUTH_CLIENT_ID in the AIUM target build settings before signing in.")
                .font(.caption)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Device code prompt

    @ViewBuilder
    private func deviceCodePrompt(userCode: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open \(url) in your browser and enter:")
                .font(.caption)
            Text(userCode)
                .font(.title2.monospaced().bold())
                .textSelection(.enabled)
            if let verificationURL = URL(string: url) {
                Button {
                    UIPasteboard.general.string = userCode
                    browserDestination = BrowserDestination(url: verificationURL)
                } label: {
                    Label("Copy Code and Open Browser", systemImage: "safari")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ProgressView("Waiting for authorization…")
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Limit input row

    @ViewBuilder
    private func limitRow(label: String, value: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }

}

// MARK: - Preview

#Preview {
    SettingsView()
}
