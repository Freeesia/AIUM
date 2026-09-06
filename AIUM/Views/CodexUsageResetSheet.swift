import SwiftUI

struct CodexUsageResetSheet: View {
    let confirmation: CodexUsageResetConfirmation
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(confirmation.accountDisplayName, systemImage: "person.crop.circle")
                        .font(.subheadline)
                        .textSelection(.enabled)

                    if let outcome = viewModel.codexResetOutcome {
                        Text(outcome.message)
                            .font(.headline)
                        if let error = viewModel.lastError {
                            Text(error)
                                .foregroundStyle(.secondary)
                        }
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isResettingCodexUsage)
                    } else {
                        Text("This uses one reset credit to reset your Codex usage limits.")
                        Text("Reset credits remaining: \(confirmation.remainingCount)")
                            .font(.headline)
                        Text("This action cannot be undone.")
                            .foregroundStyle(.secondary)

                        if let error = viewModel.codexResetError {
                            Text(error)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await viewModel.resetCodexUsage(confirmation) }
                        } label: {
                            if viewModel.isResettingCodexUsage {
                                ProgressView("Resetting…")
                            } else if viewModel.codexResetError != nil {
                                Text("Retry")
                            } else {
                                Text("Use 1 reset")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isResettingCodexUsage || viewModel.isRefreshing)
                        .accessibilityIdentifier("codex-confirm-usage-reset")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Reset Codex usage?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        if viewModel.codexResetOutcome == nil {
                            Text("Cancel")
                        } else {
                            Text("Close")
                        }
                    }
                    .disabled(viewModel.isResettingCodexUsage)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(viewModel.isResettingCodexUsage)
    }
}
