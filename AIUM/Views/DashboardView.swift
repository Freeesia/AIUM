import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var presentedSheet: DashboardSheet? = ScreenshotLaunchConfiguration.showSettings ? .settings : nil
    @State private var githubAuthenticated = false
    @State private var codexAuthenticated = false
    @State private var claudeCodeAuthenticated = false
    @AppStorage(AppSettings.githubAICreditsVisibleKey) private var showsGitHubAICredits = true
    @AppStorage(AppSettings.githubPremiumRequestsVisibleKey) private var showsGitHubPremiumRequests = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumProviderColumnWidth: CGFloat = 320

    private let contentPadding: CGFloat = 16
    private let sectionSpacing: CGFloat = 16
    private let maximumContentWidth: CGFloat = 1120

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let columnCount = providerColumnCount(for: geometry.size.width)

                ScrollView {
                    VStack(spacing: sectionSpacing) {
                        if viewModel.isDemoMode {
                            demoBanner
                        }

                        // Keep the same view identity when folding, resizing, or changing text size.
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: sectionSpacing, alignment: .top),
                                count: columnCount
                            ),
                            alignment: .leading,
                            spacing: sectionSpacing
                        ) {
                            githubSection
                            codexSection
                            claudeCodeSection
                        }

                        if let error = viewModel.lastError {
                            errorBanner(message: error)
                        }
                    }
                    .frame(maxWidth: maximumContentWidth)
                    .padding(contentPadding)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("AIUM")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentedSheet = .settings
                    } label: {
                        Image(systemName: "gear")
                    }
                    .disabled(viewModel.isResettingCodexUsage)
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
                    .disabled(viewModel.isRefreshing || viewModel.isResettingCodexUsage)
                }
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .settings:
                    SettingsView()
                case .codexReset(let confirmation):
                    CodexUsageResetSheet(confirmation: confirmation, viewModel: viewModel)
                }
            }
            .onChange(of: presentedSheet?.id) { oldID, _ in
                guard oldID == DashboardSheet.settings.id else { return }
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

    private func providerColumnCount(for availableWidth: CGFloat) -> Int {
        guard !dynamicTypeSize.isAccessibilitySize else { return 1 }
        let contentWidth = min(availableWidth - contentPadding * 2, maximumContentWidth)
        let fittingColumns = Int((contentWidth + sectionSpacing) / (minimumProviderColumnWidth + sectionSpacing))
        return min(max(fittingColumns, 1), Provider.allCases.count)
    }

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            sectionHeader(provider: .githubCopilot)
            if githubAuthenticated {
                if !showsGitHubAICredits && !showsGitHubPremiumRequests {
                    hiddenUsageCard
                } else if visibleGitHubSnapshots.isEmpty {
                    placeholderCard(provider: .githubCopilot)
                } else {
                    ForEach(visibleGitHubSnapshots) { snapshot in
                        UsageCardView(snapshot: snapshot)
                    }
                }
            } else {
                NotSignedInCardView(provider: .githubCopilot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            sectionHeader(provider: .codex)
            if codexAuthenticated {
                if viewModel.codexSnapshots.isEmpty {
                    placeholderCard(provider: .codex)
                } else {
                    ForEach(viewModel.codexSnapshots) { snapshot in
                        UsageCardView(snapshot: snapshot)
                    }
                }
                codexResetCreditsCard
            } else {
                NotSignedInCardView(provider: .codex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var claudeCodeSection: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            sectionHeader(provider: .claudeCode)
            if claudeCodeAuthenticated {
                if viewModel.claudeCodeSnapshots.isEmpty {
                    placeholderCard(provider: .claudeCode)
                } else {
                    ForEach(viewModel.claudeCodeSnapshots) { snapshot in
                        UsageCardView(snapshot: snapshot)
                    }
                }
            } else {
                NotSignedInCardView(provider: .claudeCode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var visibleGitHubSnapshots: [UsageSnapshot] {
        viewModel.githubSnapshots.filter { snapshot in
            switch snapshot.planKind {
            case .aiCredits:
                return showsGitHubAICredits
            case .premiumRequests:
                return showsGitHubPremiumRequests
            default:
                return true
            }
        }
    }

    private func updateAuthStatus() async {
        githubAuthenticated = await viewModel.githubIsAuthenticated
        codexAuthenticated = await viewModel.codexIsAuthenticated
        claudeCodeAuthenticated = await viewModel.claudeCodeIsAuthenticated
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

    private var hiddenUsageCard: some View {
        Label("All Copilot usage displays are turned off", systemImage: "eye.slash")
            .font(.subheadline)
            .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var codexResetCreditsCard: some View {
        if let resetCredits = viewModel.codexResetCredits, resetCredits > 0 {
            CodexResetCreditsCard(
                remainingCount: resetCredits,
                isDisabled: viewModel.isRefreshing || viewModel.isResettingCodexUsage || viewModel.isDemoMode
            ) {
                Task {
                    if let confirmation = await viewModel.prepareCodexUsageReset() {
                        presentedSheet = .codexReset(confirmation)
                    }
                }
            }
        }
    }
}

private enum DashboardSheet: Identifiable {
    case settings
    case codexReset(CodexUsageResetConfirmation)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .codexReset(let confirmation): return confirmation.id.uuidString
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
}
