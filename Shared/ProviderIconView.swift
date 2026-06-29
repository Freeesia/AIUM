import SwiftUI

struct ProviderIconView: View {
    let provider: Provider
    let size: CGFloat

    init(provider: Provider, size: CGFloat = 20) {
        self.provider = provider
        self.size = size
    }

    private var renderingMode: Image.TemplateRenderingMode {
        provider == .codex ? .original : .template
    }

    var body: some View {
        Image(provider.iconAssetName)
            .renderingMode(renderingMode)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
