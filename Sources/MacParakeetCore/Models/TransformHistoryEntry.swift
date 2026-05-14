import Foundation
import GRDB

public struct TransformHistoryEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var transformId: UUID?
    public var transformName: String
    public var inputText: String
    public var outputText: String
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var capturePath: String
    public var replacementPath: String
    public var llmElapsedMs: Int
    public var totalElapsedMs: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        transformId: UUID? = nil,
        transformName: String,
        inputText: String,
        outputText: String,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        capturePath: String,
        replacementPath: String,
        llmElapsedMs: Int,
        totalElapsedMs: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.transformId = transformId
        self.transformName = transformName
        self.inputText = inputText
        self.outputText = outputText
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.capturePath = capturePath
        self.replacementPath = replacementPath
        self.llmElapsedMs = llmElapsedMs
        self.totalElapsedMs = totalElapsedMs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var sourceAppDisplayName: String {
        if let sourceAppName, !sourceAppName.isEmpty {
            return sourceAppName
        }
        if let sourceAppBundleID, !sourceAppBundleID.isEmpty {
            return sourceAppBundleID
        }
        return "Unknown app"
    }
}

extension TransformHistoryEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "transform_history"

    public enum Columns: String, ColumnExpression {
        case id
        case transformId
        case transformName
        case inputText
        case outputText
        case sourceAppBundleID
        case sourceAppName
        case capturePath
        case replacementPath
        case llmElapsedMs
        case totalElapsedMs
        case createdAt
        case updatedAt
    }
}
