import Foundation

public struct BlockchairBlockResponse: Codable {
    public let data: BlockchairBlockData

    enum CodingKeys: String, CodingKey {
        case data
    }
}

public struct BlockchairBlockData: Codable {
    public let blocks: [BlockchairBlock]

    enum CodingKeys: String, CodingKey {
        case blocks
    }
}

public struct BlockchairBlock: Codable {
    public let id: Int
    public let hash: String
    public let time: String
    public let size: Int
    public let strippedSize: Int
    public let weight: Int
    public let txCount: Int
    public let reward: Decimal?

    enum CodingKeys: String, CodingKey {
        case id
        case hash
        case time
        case size
        case strippedSize = "stripped_size"
        case weight
        case txCount = "tx_count"
        case reward
    }
}

public struct BlockchairTransactionResponse: Codable {
    public let data: BlockchairTransactionData

    enum CodingKeys: String, CodingKey {
        case data
    }
}

public struct BlockchairTransactionData: Codable {
    public let transactions: [BlockchairTransaction]

    enum CodingKeys: String, CodingKey {
        case transactions
    }
}

public struct BlockchairTransaction: Codable {
    public let hash: String
    public let blockId: Int
    public let time: String
    public let size: Int
    public let fee: Decimal
    public let inputsCount: Int
    public let outputsCount: Int
    public let inputTotal: Decimal?
    public let outputTotal: Decimal?

    enum CodingKeys: String, CodingKey {
        case hash
        case blockId = "block_id"
        case time
        case size
        case fee
        case inputsCount = "inputs_count"
        case outputsCount = "outputs_count"
        case inputTotal = "input_total"
        case outputTotal = "output_total"
    }
}

public struct BlockchairOutputResponse: Codable {
    public let data: BlockchairOutputData

    enum CodingKeys: String, CodingKey {
        case data
    }
}

public struct BlockchairOutputData: Codable {
    public let outputs: [BlockchairOutput]

    enum CodingKeys: String, CodingKey {
        case outputs
    }
}

public struct BlockchairOutput: Codable {
    public let transactionHash: String
    public let index: Int
    public let value: Decimal
    public let script: String
    public let blockId: Int
    public let spent: Bool

    enum CodingKeys: String, CodingKey {
        case transactionHash = "transaction_hash"
        case index
        case value
        case script
        case blockId = "block_id"
        case spent
    }
}

public struct BlockchairStatsResponse: Codable {
    public let data: BlockchairStats

    enum CodingKeys: String, CodingKey {
        case data
    }
}

public struct BlockchairStats: Codable {
    public let bestBlockHash: String
    public let bestBlockHeight: Int
    public let bestBlockTime: String?
    public let difficulty: Decimal
    public let hashRate: Decimal?
    public let marketPriceUsd: Decimal?
    public let circulatingSupply: Decimal?
    public let totalFees: Decimal?
    public let medianFee: Decimal?
    public let secondsPerBlock: Decimal?

    enum CodingKeys: String, CodingKey {
        case bestBlockHash = "best_block_hash"
        case bestBlockHeight = "best_block_height"
        case bestBlockTime = "best_block_time"
        case difficulty
        case hashRate = "hash_rate"
        case marketPriceUsd = "market_price_usd"
        case circulatingSupply = "circulating_supply"
        case totalFees = "total_fees"
        case medianFee = "median_fee"
        case secondsPerBlock = "seconds_per_block"
    }
}

public struct BlockchairErrorResponse: Codable {
    public let error: String
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case message
    }
}

public struct BlockchairAddressDashboardsResponse: Codable {
    public let data: BlockchairAddressDashboardsData
    public let context: BlockchairDashboardContext?
}

public struct BlockchairAddressDashboardsData: Codable {
    public let addresses: [String: BlockchairDashboardAddress]
    public let transactions: [BlockchairDashboardTransaction]
}

public struct BlockchairDashboardAddress: Codable {
    public let scriptHex: String

    enum CodingKeys: String, CodingKey {
        case scriptHex = "script_hex"
    }
}

public struct BlockchairDashboardTransaction: Codable {
    public let blockId: Int?
    public let hash: String
    public let address: String

    enum CodingKeys: String, CodingKey {
        case blockId = "block_id"
        case hash
        case address
    }
}

public struct BlockchairDashboardBlocksResponse: Codable {
    public let data: [String: BlockchairDashboardBlockMap]
}

public struct BlockchairDashboardBlockMap: Codable {
    public let block: BlockchairDashboardBlock
}

public struct BlockchairDashboardBlock: Codable {
    public let hash: String
}

public struct BlockchairDashboardContext: Codable {
    public let code: Int?
    public let limit: String?
    public let offset: String?
    public let results: Int?
    public let state: Int?
}

extension String {
    public func hexToData() -> Data? {
        var hex = self
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        guard hex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        return data
    }
}

extension Data {
    public func toHexString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

extension Date {
    private static let blockchairDateParsers: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter
        }
    }()

    private static let blockchairOutputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    public init?(blockchairDateString: String) {
        for formatter in Self.blockchairDateParsers {
            if let date = formatter.date(from: blockchairDateString) {
                self = date
                return
            }
        }

        return nil
    }

    public func toBlockchairFormat() -> String {
        Self.blockchairOutputFormatter.string(from: self)
    }
}

extension BlockchairBlock {
    public func isValid() -> Bool {
        guard hash.count == 64 else { return false }
        guard let _ = hash.hexToData() else { return false }
        guard id >= 0 else { return false }
        guard time.count > 0 else { return false }
        guard txCount >= 0 else { return false }
        guard txCount < 10000 else { return false }
        return true
    }

    public var timestamp: Date? {
        return Date(blockchairDateString: time)
    }
}

extension BlockchairTransaction {
    public func isValid() -> Bool {
        guard hash.count == 64 else { return false }
        guard let _ = hash.hexToData() else { return false }
        guard blockId > 0 else { return false }
        guard inputsCount >= 0 else { return false }
        guard outputsCount >= 0 else { return false }
        return true
    }
}

extension BlockchairOutput {
    public func isValid() -> Bool {
        guard transactionHash.count == 64 else { return false }
        guard let _ = transactionHash.hexToData() else { return false }
        guard index >= 0 else { return false }
        guard value >= 0 else { return false }
        return true
    }
}
