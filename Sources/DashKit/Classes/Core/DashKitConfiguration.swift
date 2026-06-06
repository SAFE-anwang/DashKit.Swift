import Foundation

public class DashKitConfiguration {
    public enum SyncSourceStrategy {
        case legacyApi
        case hybridBlockchair
        case forceBlockchair
    }

    public static let shared = DashKitConfiguration()

    private let queue = DispatchQueue(label: "com.dashkit.configuration", attributes: .concurrent)
    private var _blockchairEnabled: Bool = false
    private var _syncSourceStrategy: SyncSourceStrategy = .legacyApi
    private var _blockchairApiKey: String?
    private var _blockchairCacheEnabled: Bool = true
    private var _blockchairSyncFrequencySeconds: TimeInterval = 60
    private var _useNativeBlockchairApi: Bool = true

    public var blockchairEnabled: Bool {
        get { queue.sync { _blockchairEnabled } }
        set {
            queue.sync(flags: .barrier) {
                self._blockchairEnabled = newValue
                self._syncSourceStrategy = newValue ? .hybridBlockchair : .legacyApi
            }
        }
    }
    public var blockchairApiKey: String? {
        get { queue.sync { _blockchairApiKey } }
        set { queue.sync(flags: .barrier) { self._blockchairApiKey = newValue } }
    }
    public var blockchairCacheEnabled: Bool {
        get { queue.sync { _blockchairCacheEnabled } }
        set { queue.sync(flags: .barrier) { self._blockchairCacheEnabled = newValue } }
    }
    public var blockchairSyncFrequencySeconds: TimeInterval {
        get { queue.sync { _blockchairSyncFrequencySeconds } }
        set { queue.sync(flags: .barrier) { self._blockchairSyncFrequencySeconds = newValue } }
    }
    public var syncSourceStrategy: SyncSourceStrategy {
        get { queue.sync { _syncSourceStrategy } }
        set {
            queue.sync(flags: .barrier) {
                self._syncSourceStrategy = newValue
                self._blockchairEnabled = newValue != .legacyApi
            }
        }
    }
    public var useNativeBlockchairApi: Bool {
        get { queue.sync { _useNativeBlockchairApi } }
        set { queue.sync(flags: .barrier) { self._useNativeBlockchairApi = newValue } }
    }

    private init() {}

    public func configure(
        blockchairEnabled: Bool = false,
        apiKey: String? = nil,
        cacheEnabled: Bool = true,
        syncFrequencySeconds: TimeInterval = 60,
        syncSourceStrategy: SyncSourceStrategy? = nil,
        useNativeBlockchairApi: Bool = true
    ) {
        queue.sync(flags: .barrier) {
            if let syncSourceStrategy {
                self._syncSourceStrategy = syncSourceStrategy
                self._blockchairEnabled = syncSourceStrategy != .legacyApi
            } else {
                self._blockchairEnabled = blockchairEnabled
                self._syncSourceStrategy = blockchairEnabled ? .hybridBlockchair : .legacyApi
            }

            self._blockchairApiKey = apiKey
            self._blockchairCacheEnabled = cacheEnabled
            self._blockchairSyncFrequencySeconds = syncFrequencySeconds
            self._useNativeBlockchairApi = useNativeBlockchairApi
        }
    }

    public func reset() {
        queue.sync(flags: .barrier) {
            self._blockchairEnabled = false
            self._syncSourceStrategy = .legacyApi
            self._blockchairApiKey = nil
            self._blockchairCacheEnabled = true
            self._blockchairSyncFrequencySeconds = 60
            self._useNativeBlockchairApi = true
        }
    }

    public func syncSourceStrategySnapshot() -> SyncSourceStrategy {
        queue.sync { _syncSourceStrategy }
    }

    public func useNativeBlockchairApiSnapshot() -> Bool {
        queue.sync { _useNativeBlockchairApi }
    }
}
