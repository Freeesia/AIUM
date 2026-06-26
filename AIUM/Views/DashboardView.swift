import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showSettings = false
    @State private var githubAuthenticated = false
    @State private var codexAuthenticated = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // GitHub Copilot section
                    sectionHeader("GitHub Copilot", systemImage: "person.crop.circle")
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
                    sectionHeader("OpenAI Codex", systemImage: "cpu.fill")
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
                Task {
                    await updateAuthStatus()
                    viewModel.restartPeriodicRefresh()
                    viewModel.refresh()
                }
            }
            .task {
                await updateAuthStatus()
                viewModel.refreshIfNeeded()
                viewModel.startPeriodicRefresh()
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
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
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
