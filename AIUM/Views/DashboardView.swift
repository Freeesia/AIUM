import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showSettings = ScreenshotLaunchConfiguration.showSettings
    @State private var githubAuthenticated = false
    @State private var codexAuthenticated = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Demo mode banner
                    if viewModel.isDemoMode {
                        demoBanner
                    }

                    // GitHub Copilot section
                    sectionHeader(provider: .githubCopilot)
                    if githubAuthenticated {
                        if viewModel.githubSnapshots.isEmpty {
                            placeholderCard(provider: .githubCopilot)
                        } else {
                            ForEach(viewModel.githubSnapshots) { snapshot in
                                UsageCardView(snapshot: snapshot)
                            }
                        }
                    } else {
                        NotSignedInCardView(provider: .githubCopilot)
                    }

                    // OpenAI Codex section
                    sectionHeader(provider: .codex)
                    if codexAuthenticated {
                        if viewModel.codexSnapshots.isEmpty {
                            placeholderCard(provider: .codex)
                        } else {
                            ForEach(viewModel.codexSnapshots) { snapshot in
                                UsageCardView(snapshot: snapshot)
                            }
                        }
                    } else {
                        NotSignedInCardView(provider: .codex)
                    }

                    // Error banner
                    if let error = viewModel.lastError {
                        errorBanner(message: error)
                    }
                }
                .padding()
            }
            .navigationTitle("AIUM")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isRefreshing)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: showSettings) { _, isPresented in
                guard !isPresented else { return }
                viewModel.reloadDemoMode()
                Task {
                    await updateAuthStatus()
                    viewModel.restartPeriodicRefresh()
                    viewModel.refresh()
                }
            }
            .task {
                viewModel.reloadDemoMode()
                await updateAuthStatus()
                viewModel.refreshIfNeeded()
                viewModel.startPeriodicRefresh()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification
                )
            ) { _ in
                viewModel.reloadDemoMode()
                Task { await updateAuthStatus() }
            }
            .refreshable {
                viewModel.refresh()
            }
        }
    }

    // MARK: - Helpers

    private func updateAuthStatus() async {
        githubAuthenticated = await viewModel.githubIsAuthenticated
        codexAuthenticated = await viewModel.codexIsAuthenticated
    }

    @ViewBuilder
    private var demoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text("Demo Mode — sample data is shown. No account is required.")
                .font(.caption)
                .foregroundStyle(.blue)
            Spacer()
        }
        .padding()
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func sectionHeader(provider: Provider) -> some View {
        HStack {
            Label {
                Text(provider.displayName)
            } icon: {
                ProviderIconView(provider: provider, size: 22)
            }
                .font(.title3.bold())
            Spacer()
        }
    }

    @ViewBuilder
    private func placeholderCard(provider: Provider) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
}
