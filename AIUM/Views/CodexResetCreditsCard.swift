import SwiftUI

struct CodexResetCreditsCard: View {
    let remainingCount: Int
    let isDisabled: Bool
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Usage resets available")
                        .font(.headline)
                    Text("Reset credits remaining: \(remainingCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Button("Reset usage", action: onReset)
                .buttonStyle(.bordered)
                .disabled(isDisabled)
                .accessibilityIdentifier("codex-reset-usage")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Available resets") {
    CodexResetCreditsCard(remainingCount: 2, isDisabled: false, onReset: {})
        .padding()
}

#Preview("Reset in progress") {
    CodexResetCreditsCard(remainingCount: 1, isDisabled: true, onReset: {})
        .padding()
}
