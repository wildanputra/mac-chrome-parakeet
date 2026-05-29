import XCTest
@testable import MacParakeetCore

/// Guards the `meeting-vad-sim` harness logic (batching loop + report assembly).
/// Fixed mode only, so no FluidAudio model is required — CI-safe and
/// deterministic. The VAD strategy itself is covered by
/// `SpeechBoundaryMeetingLiveAudioChunkerTests`.
final class MeetingVADChunkingSimulatorTests: XCTestCase {
    private func tone(seconds: Double) -> [Float] {
        let n = Int(seconds * 16_000)
        return (0..<n).map { Float(sin(Double($0) * 0.05)) * 0.3 }
    }

    func testFixedModeReplayMatchesDirectChunker() async {
        let samples = tone(seconds: 23)

        // Drive the production fixed chunker directly in the same batch cadence
        // the simulator uses, to assert the harness doesn't drop or reshape audio.
        let direct = FixedMeetingLiveAudioChunker()
        await direct.reset()
        var expected: [AudioChunker.AudioChunk] = []
        let batch = 1600
        var off = 0
        while off < samples.count {
            let end = min(off + batch, samples.count)
            expected += await direct.addSamples(Array(samples[off..<end]))
            off = end
        }
        if let tail = await direct.flush() { expected.append(tail) }

        let report = await MeetingVADChunkingSimulator.simulate(
            samples16k: samples, mode: .fixed, batchSamples: batch)

        XCTAssertEqual(report.mode, "fixed")
        XCTAssertTrue(report.vadAvailable)
        XCTAssertEqual(report.audioDurationMs, 23_000)
        XCTAssertEqual(report.chunks.count, expected.count, "harness must not drop or add chunks")
        for (got, want) in zip(report.chunks, expected) {
            XCTAssertEqual(got.startMs, want.startMs)
            XCTAssertEqual(got.endMs, want.endMs)
            XCTAssertEqual(got.sampleCount, want.samples.count)
        }
        XCTAssertGreaterThan(report.processingSeconds, 0)
        XCTAssertGreaterThan(report.realtimeFactor, 0)
        // Fixed strategy reports no VAD diagnostics.
        XCTAssertEqual(report.forceEmits, 0)
        XCTAssertEqual(report.droppedSilenceWindows, 0)
        XCTAssertFalse(report.fellBackToFixed)
    }

    func testUnevenBatchCoversAllAudio() async {
        // A batch size that doesn't divide the input must still feed the trailing
        // partial batch (no lost tail).
        let samples = tone(seconds: 12)
        let report = await MeetingVADChunkingSimulator.simulate(
            samples16k: samples, mode: .fixed, batchSamples: 1500)
        XCTAssertEqual(report.audioDurationMs, 12_000)
        // 12s of audio → at least the first 5s fixed chunk plus a flushed tail.
        XCTAssertGreaterThanOrEqual(report.chunks.count, 2)
        // Contiguity: fixed chunks advance by 4s (5s window, 1s overlap).
        if report.chunks.count >= 2 {
            XCTAssertEqual(report.chunks[0].startMs, 0)
            XCTAssertEqual(report.chunks[1].startMs, 4_000)
        }
    }
}
