import SwiftUI

struct CodexUsageResetSheet: View {
    let confirmation: CodexUsageResetConfirmation
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let accountName = confirmation.accountDisplayName {
                        Label(accountName, systemImage: "person.crop.circle")
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }

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
                        Text("Reset credits remaining: \(viewModel.codexResetCreditDetails?.availableCount ?? confirmation.remainingCount)")
                            .font(.headline)
                        resetCreditExpirations
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
                        .disabled(viewModel.isResettingCodexUsage || viewModel.isRefreshing
                                  || viewModel.isLoadingCodexResetCreditDetails
                                  || viewModel.codexResetCreditDetails?.availableCount == 0)
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
        .task(id: confirmation.id) {
            await viewModel.loadCodexResetCreditDetails(for: confirmation)
        }
    }

    private var resetCreditExpirations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reset credit expiration dates")
                .font(.headline)

            if viewModel.isLoadingCodexResetCreditDetails {
                ProgressView("Loading expiration dates…")
            } else if let error = viewModel.codexResetCreditDetailsError {
                Text(error)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await viewModel.loadCodexResetCreditDetails(for: confirmation) }
                }
                .disabled(viewModel.isResettingCodexUsage)
            } else if let details = viewModel.codexResetCreditDetails {
                if details.credits.isEmpty {
                    if details.availableCount == 0 {
                        Text("No reset credits are available.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Expiration date unavailable")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(details.credits) { credit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(credit.displayTitle)
                                .font(.subheadline.weight(.medium))
                            if let expiresAt = credit.expiresAt {
                                Text("Expires \(Text(expiresAt, format: .dateTime.year().month().day().hour().minute().timeZone(.specificName(.short))))")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Expiration date unavailable")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
