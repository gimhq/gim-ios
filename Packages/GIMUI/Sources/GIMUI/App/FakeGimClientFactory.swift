import GIMClientKit

/// Demo client factory. `AppModel` uses it until the gim-core bindings provide the real factory.
public struct FakeGimClientFactory: GimClientFactory {
    public init() {}

    public func make(hooks: PlatformHooks) async throws -> any GimClientAPI {
        FakeGimClient.demo(dataDirectory: hooks.dataDirectory)
    }
}
