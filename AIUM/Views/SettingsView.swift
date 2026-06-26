import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // GitHub section
                Section {
                    if !viewModel.isGitHubClientIdConfigured {
                        clientIdWarning
                    }
                    githubAuthRow
                    githubBillingOrganizationRow
                    githubBillingTokenRow
                    if viewModel.isGitHubAuthenticated {
                        limitRow(label: "AI Credit Limit", value: $viewModel.aiCreditMonthlyLimit,
                                 placeholder: "e.g. 1000")
                        limitRow(label: "Premium Request Limit", value: $viewModel.premiumRequestMonthlyLimit,
                                 placeholder: "e.g. 300")
                    }
                } header: {
                    Text("GitHub Copilot")
                } footer: {
                    githubFooter
                }

                // Codex section
                Section {
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
                } header: {
                    Text("OpenAI Codex")
                } footer: {
                    codexWarningFooter
                }

                // Refresh interval
                Section("Refresh") {
                    Picker("Interval", selection: $viewModel.refreshIntervalMinutes) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("6 hours").tag(360)
                    }
                }

                // App Group info
                Section("App Group") {
                    HStack {
                        Text("Identifier")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(UsageStore.appGroupIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text("The App Group must be configured in both the AIUM target and the AIUMWidget target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        Text("Leave Billing Organization blank for a personally billed Copilot plan. For organization-billed seats, enter the organization slug and save a token with Organization permissions > Administration: Read-only. Set monthly limits manually because the billing report does not return your plan allowance.")
    }

    @ViewBuilder
    private var githubBillingOrganizationRow: some View {
        HStack {
            Text("Billing Organization")
            Spacer()
            TextField("optional org slug", text: $viewModel.githubBillingOrganization)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var githubBillingTokenRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Fine-grained PAT for billing usage", text: $viewModel.githubManualAccessToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                viewModel.saveGitHubManualAccessToken()
            } label: {
                Label("Save Billing Token", systemImage: "key.fill")
            }
            .disabled(viewModel.githubManualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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
                Link("Open in Browser", destination: verificationURL)
                    .font(.caption)
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

    // MARK: - Codex warning footer

    private var codexWarningFooter: some View {
        Text("⚠️ AIUM uses private OpenAI/Codex API endpoints that are not officially supported. These may change or stop working at any time. Do NOT use this app commercially or submit it to the App Store until official APIs are available.")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
