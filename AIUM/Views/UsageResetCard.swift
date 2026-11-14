import SwiftUI

struct UsageResetCard: View {
    let remainingCount: Int
    let accessibilityIdentifier: String
    let isDisabled: Bool
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Usage reset")
                        .font(.headline)
                    Text("\(remainingCount) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button("Reset", action: onReset)
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(isDisabled)
                .accessibilityLabel("Reset usage")
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Available resets") {
    UsageResetCard(remainingCount: 2, accessibilityIdentifier: "codex-reset-usage", isDisabled: false, onReset: {})
        .padding()
}

#Preview("Reset in progress") {
    UsageResetCard(remainingCount: 1, accessibilityIdentifier: "codex-reset-usage", isDisabled: true, onReset: {})
        .padding()
}
