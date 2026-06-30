import SwiftUI

struct ProviderIconView: View {
    let provider: Provider
    let size: CGFloat

    init(provider: Provider, size: CGFloat = 20) {
        self.provider = provider
        self.size = size
    }

    var body: some View {
        Image(provider.iconAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
