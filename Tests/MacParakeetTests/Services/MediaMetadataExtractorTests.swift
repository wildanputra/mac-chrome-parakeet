import AVFoundation
import XCTest
@testable import MacParakeetCore

private final class SendableAssetWriter: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

final class MediaMetadataExtractorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-metadata-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testExtractsCommonMetadataFromTaggedM4A() async throws {
        let artwork = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let fileURL = tempDir.appendingPathComponent("tagged.m4a")
        try await writeTaggedAudio(
            to: fileURL,
            title: "Tagged Episode",
            artist: "Tagged Author",
            artwork: artwork
        )

        let metadata = await AVMediaMetadataExtractor().metadata(for: fileURL)

        XCTAssertEqual(metadata.title, "Tagged Episode")
        XCTAssertEqual(metadata.author, "Tagged Author")
        XCTAssertEqual(metadata.artworkData, artwork)
        XCTAssertGreaterThan(metadata.durationMs ?? 0, 0)
    }

    private func writeTaggedAudio(
        to outputURL: URL,
        title: String,
        artist: String,
        artwork: Data
    ) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        writer.metadata = [
            metadataItem(identifier: .commonIdentifierTitle, value: title as NSString),
            metadataItem(identifier: .commonIdentifierArtist, value: artist as NSString),
            metadataItem(identifier: .commonIdentifierArtwork, value: artwork as NSData),
        ]

        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
        )
        guard writer.canAdd(input) else {
            throw TestError.cannotAddWriterInput
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? TestError.writerStartFailed
        }
        writer.startSession(atSourceTime: .zero)

        let sampleBuffer = try PCMBufferToSampleBuffer().makeSampleBuffer(
            from: makeSineBuffer(frameCount: 48_000),
            presentationTimeSamples: 0
        )
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard input.append(sampleBuffer) else {
            throw writer.error ?? TestError.sampleAppendFailed
        }
        input.markAsFinished()

        let sendableWriter = SendableAssetWriter(writer)
        try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                let writer = sendableWriter.writer
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writer.error ?? TestError.finishFailed)
                }
            }
        }
    }

    private func metadataItem(identifier: AVMetadataIdentifier, value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    private func makeSineBuffer(frameCount: Int) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw TestError.failedToCreateBuffer
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let phase = 2 * Double.pi * 220 * Double(index) / 48_000.0
            samples[index] = Float(sin(phase) * 0.2)
        }
        return buffer
    }

    private enum TestError: Error {
        case cannotAddWriterInput
        case failedToCreateBuffer
        case finishFailed
        case sampleAppendFailed
        case writerStartFailed
    }
}
