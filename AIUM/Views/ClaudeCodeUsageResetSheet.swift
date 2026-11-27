import SwiftUI

struct ClaudeCodeUsageResetSheet: View {
    let confirmation: ClaudeCodeUsageResetConfirmation
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

                    if let outcome = viewModel.claudeCodeResetOutcome {
                        Text(outcome.message)
                            .font(.headline)
                        if let error = viewModel.lastError {
                            Text(error)
                                .foregroundStyle(.secondary)
                        }
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isResettingClaudeCodeUsage)
                    } else {
                        Text("This uses one reset to reset your Claude Code usage limits.")
                        Text("Resets remaining: \(remainingCount)")
                            .font(.headline)
                        resetGrants
                        Text("This action cannot be undone.")
                            .foregroundStyle(.secondary)

                        if let error = viewModel.claudeCodeResetError {
                            Text(error)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await viewModel.resetClaudeCodeUsage(confirmation) }
                        } label: {
                            if viewModel.isResettingClaudeCodeUsage {
                                ProgressView("Resetting…")
                            } else if viewModel.claudeCodeResetError != nil {
                                Text("Retry")
                            } else {
                                Text("Use 1 reset")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isResettingClaudeCodeUsage || viewModel.isRefreshing
                                  || viewModel.isLoadingClaudeCodeResetStatus
                                  || viewModel.claudeCodeResetGrantToUse == nil)
                        .accessibilityIdentifier("claude-code-confirm-usage-reset")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Reset Claude Code usage?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        if viewModel.claudeCodeResetOutcome == nil {
                            Text("Cancel")
                        } else {
                            Text("Close")
                        }
                    }
                    .disabled(viewModel.isResettingClaudeCodeUsage)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(viewModel.isResettingClaudeCodeUsage)
        .task(id: confirmation.id) {
            await viewModel.loadClaudeCodeResetStatus(for: confirmation)
        }
    }

    private var remainingCount: Int {
        viewModel.claudeCodeResetStatus?.availableCount() ?? confirmation.remainingCount
    }

    private var resetGrants: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available resets")
                .font(.headline)

            if let status = viewModel.claudeCodeResetStatus {
                let grants = status.activeGrants()
                if grants.isEmpty || !status.eligible {
                    Text("No resets are available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(grants) { grant in
                        grantRow(grant, isSelected: grant.id == viewModel.claudeCodeResetGrantToUse?.id)
                    }
                    if viewModel.claudeCodeResetGrantToUse == nil {
                        Text("No reset can be used right now.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.isLoadingClaudeCodeResetStatus {
                ProgressView("Loading reset details…")
            } else if let error = viewModel.claudeCodeResetStatusError {
                Text(error)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await viewModel.loadClaudeCodeResetStatus(for: confirmation) }
                }
                .disabled(viewModel.isResettingClaudeCodeUsage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func grantRow(_ grant: ClaudeCodeResetGrant, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(grant.displayTitle)
                    .font(.subheadline.weight(.medium))
                if let kindDescription = grant.kindDescription {
                    Text(kindDescription)
                        .foregroundStyle(.secondary)
                }
                Text("\(grant.resetsLeft) remaining")
                    .foregroundStyle(.secondary)
                if let endsAt = grant.endsAt {
                    Text("Expires \(Text(endsAt, format: .dateTime.year().month().day().hour().minute().timeZone(.specificName(.short))))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Expiration date unavailable")
                        .foregroundStyle(.secondary)
                }
                if !grant.usableNow {
                    if grant.useRequiresLimit {
                        Text("Can be used after you reach a usage limit.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Can't be used right now.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
