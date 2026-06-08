import BitcoinCore
import Foundation

public class FallbackApiTransactionProvider: IApiTransactionProvider {
    private let primaryProvider: IApiTransactionProvider
    private let fallbackProvider: IApiTransactionProvider

    public init(primaryProvider: IApiTransactionProvider, fallbackProvider: IApiTransactionProvider) {
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
    }

    public func transactions(addresses: [String], stopHeight: Int?) async throws -> [ApiTransactionItem] {
        do {
            return try await primaryProvider.transactions(addresses: addresses, stopHeight: stopHeight)
        } catch let error as BlockchairError where error.shouldFallback {
            return try await fallbackProvider.transactions(addresses: addresses, stopHeight: stopHeight)
        } catch {
            throw error
        }
    }
}
