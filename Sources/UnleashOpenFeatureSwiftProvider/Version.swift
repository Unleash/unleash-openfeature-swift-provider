/// This provider reports to Unleash as the SDK "flavor", sent alongside
/// the underlying Swift SDK's own `unleash-sdk` header so adoption of the
/// OpenFeature provider can be tracked.
enum ProviderInfo {
    /// Bump this on every release and tag the repo with the matching version,
    /// so the flavour version can never drift from what is published
    static let version = "0.1.0"

    static let name = "unleash-openfeature-swift-provider"
    static let sdkFlavor: String = name
    static let sdkFlavorVersion: String = version
}
