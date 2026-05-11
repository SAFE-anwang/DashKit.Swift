import Foundation
import HsToolKit
import BitcoinCore

public enum BlockchairError: Error {
    case networkUnavailable
    case connectionTimeout
    case invalidApiKey
    case rateLimitExceeded(retryAfter: TimeInterval)
    case resourceNotFound
    case serverError(message: String)
    case parseError(details: String)
    case validationError(field: String, reason: String)

    public var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .connectionTimeout, .rateLimitExceeded, .serverError:
            return true
        case .invalidApiKey, .resourceNotFound, .parseError, .validationError:
            return false
        }
    }

    public var retryDelay: TimeInterval {
        switch self {
        case .rateLimitExceeded(let retryAfter):
            return max(retryAfter, 60)
        case .networkUnavailable, .connectionTimeout:
            return 5
        case .serverError:
            return 30
        default:
            return 0
        }
    }
}

public class RateLimitHandler {
    private let maxRequestsPerMinute: Int
    private var requestTimestamps: [Date] = []
    private let queue = DispatchQueue(label: "com.dashkit.ratelimit")

    public init(maxRequestsPerMinute: Int = 60) {
        self.maxRequestsPerMinute = maxRequestsPerMinute
    }

    public func canProceed() -> Bool {
        queue.sync {
            let cutoff = Date().addingTimeInterval(-60)
            requestTimestamps = requestTimestamps.filter { $0 > cutoff }
            return requestTimestamps.count < maxRequestsPerMinute
        }
    }

    public func recordRequest() {
        queue.async { [weak self] in
            self?.requestTimestamps.append(Date())
        }
    }

    public func waitTime() -> TimeInterval {
        queue.sync {
            let cutoff = Date().addingTimeInterval(-60)
            requestTimestamps = requestTimestamps.filter { $0 > cutoff }
            guard requestTimestamps.count >= maxRequestsPerMinute else { return 0 }
            let oldestRequest = requestTimestamps.first!
            return max(0, 60 - Date().timeIntervalSince(oldestRequest))
        }
    }
}

public class DashBlockchairApiClient {
    private let baseUrl: String
    private let chainId: String
    private let logger: Logger?
    private let session: URLSession
    private let rateLimitHandler: RateLimitHandler
    private let maxRetries = 3
    private let apiKey: String?
    private let addressBatchSize = 100
    private let transactionPageLimit = 10_000

    public init(baseUrl: String, chainId: String, logger: Logger? = nil) {
        self.baseUrl = baseUrl
        self.chainId = chainId
        self.logger = logger
        self.apiKey = DashKitConfiguration.shared.blockchairApiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        self.session = URLSession(configuration: config)
        self.rateLimitHandler = RateLimitHandler(maxRequestsPerMinute: 60)
    }

    public func fetchBlocks(startHeight: Int, endHeight: Int) async throws -> [BlockchairBlock] {
        guard rateLimitHandler.canProceed() else {
            let waitTime = rateLimitHandler.waitTime()
            throw BlockchairError.rateLimitExceeded(retryAfter: waitTime)
        }

        rateLimitHandler.recordRequest()

        let url = try buildUrl(path: "/blocks", queryItems: [URLQueryItem(name: "height[]", value: "\(startHeight)..\(endHeight)")])
        let response: BlockchairBlockResponse = try await performRequest(url: url)
        return response.data.blocks.filter { $0.isValid() }
    }

    public func fetchBlock(height: Int) async throws -> BlockchairBlock {
        guard rateLimitHandler.canProceed() else {
            let waitTime = rateLimitHandler.waitTime()
            throw BlockchairError.rateLimitExceeded(retryAfter: waitTime)
        }

        rateLimitHandler.recordRequest()

        let url = try buildUrl(path: "/blocks/\(height)")
        let response: BlockchairBlockResponse = try await performRequest(url: url)
        guard let block = response.data.blocks.first(where: { $0.isValid() }) else {
            throw BlockchairError.parseError(details: "Empty or invalid block payload")
        }
        return block
    }

    public func fetchTransactions(hashes: [String]) async throws -> [BlockchairTransaction] {
        guard rateLimitHandler.canProceed() else {
            let waitTime = rateLimitHandler.waitTime()
            throw BlockchairError.rateLimitExceeded(retryAfter: waitTime)
        }

        guard !hashes.isEmpty else { return [] }

        rateLimitHandler.recordRequest()

        let queryItems = hashes.map { URLQueryItem(name: "hash", value: $0) }
        let url = try buildUrl(path: "/transactions", queryItems: queryItems)
        let response: BlockchairTransactionResponse = try await performRequest(url: url)
        return response.data.transactions.filter { $0.isValid() }
    }

    public func fetchTransaction(hash: String) async throws -> BlockchairTransaction {
        guard rateLimitHandler.canProceed() else {
            let waitTime = rateLimitHandler.waitTime()
            throw BlockchairError.rateLimitExceeded(retryAfter: waitTime)
        }

        rateLimitHandler.recordRequest()

        let url = try buildUrl(path: "/transactions/\(hash)")
        let response: BlockchairTransactionResponse = try await performRequest(url: url)
        guard let transaction = response.data.transactions.first(where: { $0.isValid() }) else {
            throw BlockchairError.parseError(details: "Empty or invalid transaction payload")
        }
        return transaction
    }

    public func fetchOutputs(address: String, limit: Int = 100) async throws -> [BlockchairOutput] {
        guard rateLimitHandler.canProceed() else {
            let waitTime = rateLimitHandler.waitTime()
            throw BlockchairError.rateLimitExceeded(retryAfter: waitTime)
        }

        rateLimitHandler.recordRequest()

        let url = try buildUrl(
            path: "/outputs",
            queryItems: [
                URLQueryItem(name: "recipient", value: address),
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "spent", value: "false"),
            ]
        )
        let response: BlockchairOutputResponse = try await performRequest(url: url)
        return response.data.outputs.filter { $0.isValid() }
    }

    public func fetchStats() async throws -> BlockchairStats {
        guard rateLimitHandler.canProceed() else {
            let waitTime = rateLimitHandler.waitTime()
            throw BlockchairError.rateLimitExceeded(retryAfter: waitTime)
        }

        rateLimitHandler.recordRequest()

        let url = try buildUrl(path: "/stats")
        let response: BlockchairStatsResponse = try await performRequest(url: url)
        return response.data
    }

    public func fetchAddressTransactions(addresses: [String], stopHeight: Int?) async throws -> [ApiTransactionItem] {
        guard !addresses.isEmpty else { return [] }

        var transactionItemsMap = [String: ApiTransactionItem]()

        for chunk in addresses.chunked(into: addressBatchSize) {
            let (addressItems, transactions) = try await fetchDashboardTransactions(addresses: chunk, stopHeight: stopHeight)

            for transaction in transactions {
                guard let blockHeight = transaction.blockId else {
                    continue
                }

                if transactionItemsMap[transaction.hash] == nil {
                    transactionItemsMap[transaction.hash] = ApiTransactionItem(
                        blockHash: "",
                        blockHeight: blockHeight,
                        apiAddressItems: []
                    )
                }

                if let addressItem = addressItems.first(where: { transaction.address == $0.address }) {
                    transactionItemsMap[transaction.hash]?.apiAddressItems.append(addressItem)
                }
            }
        }

        return Array(transactionItemsMap.values)
    }

    public func fetchBlockHashes(heights: [Int]) async throws -> [Int: String] {
        let uniqueHeights = Array(Set(heights)).sorted()
        guard !uniqueHeights.isEmpty else { return [:] }

        var hashesMap = [Int: String]()

        for chunk in uniqueHeights.chunked(into: 10) {
            let heightsValue = chunk.map(String.init).joined(separator: ",")
            let url = try buildUrl(
                path: "/dashboards/blocks/\(heightsValue)",
                queryItems: [URLQueryItem(name: "limit", value: "0")]
            )

            let response: BlockchairDashboardBlocksResponse = try await performRequest(url: url)
            for (key, value) in response.data {
                guard let height = Int(key) else { continue }
                hashesMap[height] = value.block.hash
            }
        }

        return hashesMap
    }

    private func fetchDashboardTransactions(addresses: [String], stopHeight: Int?, offset: Int = 0, receivedScripts: [ApiAddressItem] = [], receivedTransactions: [BlockchairDashboardTransaction] = []) async throws -> ([ApiAddressItem], [BlockchairDashboardTransaction]) {
        let url = try buildUrl(
            path: "/dashboards/addresses/\(addresses.joined(separator: ","))",
            queryItems: [
                URLQueryItem(name: "transaction_details", value: "true"),
                URLQueryItem(name: "limit", value: "\(transactionPageLimit),0"),
                URLQueryItem(name: "offset", value: "\(offset),0"),
            ]
        )

        let response: BlockchairAddressDashboardsResponse = try await performRequest(url: url)
        let scriptsSlice = response.data.addresses.map { ApiAddressItem(script: $0.value.scriptHex, address: $0.key) }
        let filteredTransactions = response.data.transactions.filter { transaction in
            guard let height = transaction.blockId, let stopHeight else {
                return true
            }
            return stopHeight < height
        }
        let scriptsMerged = receivedScripts + scriptsSlice
        let transactionsMerged = receivedTransactions + filteredTransactions

        if filteredTransactions.count < transactionPageLimit {
            return (scriptsMerged, transactionsMerged)
        }

        return try await fetchDashboardTransactions(
            addresses: addresses,
            stopHeight: stopHeight,
            offset: offset + filteredTransactions.count,
            receivedScripts: scriptsMerged,
            receivedTransactions: transactionsMerged
        )
    }

    private func performRequest<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }

        var lastError: Error = BlockchairError.networkUnavailable

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BlockchairError.networkUnavailable
                }

                switch httpResponse.statusCode {
                case 200...299:
                    do {
                        let decoder = JSONDecoder()
                        return try decoder.decode(T.self, from: data)
                    } catch {
                        throw BlockchairError.parseError(details: error.localizedDescription)
                    }

                case 401:
                    throw BlockchairError.invalidApiKey

                case 403:
                    if let errorResponse = try? JSONDecoder().decode(BlockchairErrorResponse.self, from: data) {
                        throw BlockchairError.serverError(message: errorResponse.error)
                    }
                    throw BlockchairError.invalidApiKey

                case 404:
                    throw BlockchairError.resourceNotFound

                case 429:
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        .flatMap { Double($0) } ?? 60
                    throw BlockchairError.rateLimitExceeded(retryAfter: retryAfter)

                case 500...599:
                    throw BlockchairError.serverError(message: "Server error: \(httpResponse.statusCode)")

                default:
                    throw BlockchairError.serverError(message: "Unexpected status code: \(httpResponse.statusCode)")
                }

            } catch let error as BlockchairError {
                if error.isRetryable && attempt < maxRetries - 1 {
                    lastError = error
                    let delay = calculateRetryDelay(attempt: attempt, error: error)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = calculateRetryDelay(attempt: attempt, error: error)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw BlockchairError.networkUnavailable
            }
        }

        throw lastError
    }

    private func buildUrl(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard !chainId.isEmpty else {
            throw BlockchairError.validationError(field: "chainId", reason: "Empty chain id")
        }
        guard var components = URLComponents(string: "\(baseUrl)\(path)") else {
            throw BlockchairError.validationError(field: "url", reason: "Invalid URL format")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw BlockchairError.validationError(field: "url", reason: "Failed to build URL components")
        }
        return url
    }

    private func calculateRetryDelay(attempt: Int, error: Error) -> TimeInterval {
        if let blockchairError = error as? BlockchairError {
            if case .rateLimitExceeded(let retryAfter) = blockchairError {
                return max(retryAfter, pow(2.0, Double(attempt)))
            }
            return blockchairError.retryDelay
        }
        return min(60, pow(2.0, Double(attempt)))
    }
}

extension DashBlockchairApiClient {
    public static func createForMainNet(logger: Logger? = nil) -> DashBlockchairApiClient {
        return DashBlockchairApiClient(
            baseUrl: "https://api.blockchair.com/dash",
            chainId: "dash-mainnet",
            logger: logger
        )
    }

    public static func createForTestNet(logger: Logger? = nil) -> DashBlockchairApiClient {
        return DashBlockchairApiClient(
            baseUrl: "https://api.blockchair.com/dash/testnet",
            chainId: "dash-testnet",
            logger: logger
        )
    }
}

public class NativeBlockchairTransactionProvider: IApiTransactionProvider {
    private let apiClient: DashBlockchairApiClient

    public init(apiClient: DashBlockchairApiClient) {
        self.apiClient = apiClient
    }

    public func transactions(addresses: [String], stopHeight: Int?) async throws -> [ApiTransactionItem] {
        let items = try await apiClient.fetchAddressTransactions(addresses: addresses, stopHeight: stopHeight)
        let hashesMap = try await apiClient.fetchBlockHashes(heights: items.map(\.blockHeight))

        return items.compactMap { item in
            guard let blockHash = hashesMap[item.blockHeight] else {
                return nil
            }
            return ApiTransactionItem(blockHash: blockHash, blockHeight: item.blockHeight, apiAddressItems: item.apiAddressItems)
        }
    }
}
