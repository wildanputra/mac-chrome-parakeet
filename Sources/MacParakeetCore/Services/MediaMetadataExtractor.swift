import AVFoundation
import Foundation

public struct MediaMetadata: Equatable, Sendable {
    public var title: String?
    public var author: String?
    public var description: String?
    public var artworkData: Data?
    public var durationMs: Int?

    public init(
        title: String? = nil,
        author: String? = nil,
        description: String? = nil,
        artworkData: Data? = nil,
        durationMs: Int? = nil
    ) {
        self.title = Self.normalized(title)
        self.author = Self.normalized(author)
        self.description = Self.normalized(description)
        self.artworkData = artworkData
        self.durationMs = durationMs
    }

    public static let empty = MediaMetadata()

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public protocol MediaMetadataExtracting: Sendable {
    func metadata(for fileURL: URL) async -> MediaMetadata
}

public actor AVMediaMetadataExtractor: MediaMetadataExtracting {
    public init() {}

    public func metadata(for fileURL: URL) async -> MediaMetadata {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let asset = AVURLAsset(url: fileURL)
        let durationMs = await loadDurationMs(from: asset)
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let metadata = (try? await asset.load(.metadata)) ?? []
        let items = commonMetadata + metadata

        return MediaMetadata(
            title: await firstString(
                in: items,
                matching: [
                    "title",
                    "tit2",
                    "©nam",
                    "com.apple.quicktime.title",
                ]
            ),
            author: await firstString(
                in: items,
                matching: [
                    "artist",
                    "author",
                    "creator",
                    "albumartist",
                    "tpe1",
                    "tpe2",
                    "©art",
                    "aart",
                    "com.apple.quicktime.artist",
                    "com.apple.quicktime.author",
                ]
            ),
            description: await firstString(
                in: items,
                matching: [
                    "description",
                    "comment",
                    "desc",
                    "comm",
                    "©des",
                    "ldes",
                    "com.apple.quicktime.description",
                ]
            ),
            artworkData: await firstArtworkData(in: items),
            durationMs: durationMs
        )
    }

    private func loadDurationMs(from asset: AVURLAsset) async -> Int? {
        guard let duration = try? await asset.load(.duration),
              duration.isNumeric,
              duration.seconds.isFinite,
              duration.seconds > 0
        else {
            return nil
        }
        return Int((duration.seconds * 1000).rounded())
    }

    private func firstString(in items: [AVMetadataItem], matching keys: Set<String>) async -> String? {
        for item in items where matches(item, keys: keys) {
            if let value = try? await item.load(.stringValue),
               let normalized = MediaMetadata(title: value).title
            {
                return normalized
            }
        }
        return nil
    }

    private func firstArtworkData(in items: [AVMetadataItem]) async -> Data? {
        let artworkKeys: Set<String> = [
            "artwork",
            "apic",
            "covr",
            "com.apple.quicktime.artwork",
        ]

        for item in items where matches(item, keys: artworkKeys) {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
            if let value = try? await item.load(.value) {
                if let data = value as? Data, !data.isEmpty {
                    return data
                }
                if let dictionary = value as? [String: Any],
                   let data = dictionary["data"] as? Data,
                   !data.isEmpty
                {
                    return data
                }
            }
        }

        return nil
    }

    private func matches(_ item: AVMetadataItem, keys: Set<String>) -> Bool {
        if let commonKey = item.commonKey?.rawValue.lowercased(),
           keys.contains(commonKey)
        {
            return true
        }

        if let identifier = item.identifier?.rawValue.lowercased() {
            if keys.contains(identifier) {
                return true
            }
            if keys.contains(where: { identifier.hasSuffix(".\($0)") || identifier.contains($0) }) {
                return true
            }
        }

        if let key = item.key as? String {
            return keys.contains(key.lowercased())
        }

        return false
    }
}
