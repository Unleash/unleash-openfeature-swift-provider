/// This provider reports to Unleash as the SDK "flavor", sent alongside
/// the underlying Swift SDK's own `unleash-sdk` header so adoption of the
/// OpenFeature provider can be tracked.
enum ProviderInfo {
    static let name = "unleash-openfeature-swift-provider"
    static var sdkFlavor: String = { "\(name):\(version)" }
    static let sdkFlavorVersion = "0.1.0"
}
