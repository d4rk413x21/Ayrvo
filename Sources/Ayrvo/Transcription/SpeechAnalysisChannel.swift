import AVFoundation
import Foundation
import Speech

final class SpeechAnalysisChannel: Sendable {
  let speakerID: String
  let rawContinuation: AsyncStream<AudioPCM.CopiedBuffer>.Continuation
  private let tasks: [Task<Void, Never>]

  init(
    speakerID: String,
    rawContinuation: AsyncStream<AudioPCM.CopiedBuffer>.Continuation,
    tasks: [Task<Void, Never>]
  ) {
    self.speakerID = speakerID
    self.rawContinuation = rawContinuation
    self.tasks = tasks
  }

  func finish() async { for t in tasks { _ = await t.value } }

  static func make(
    locale: Locale, speakerID: String,
    onResult: @escaping @Sendable (SpeechTranscriber.Result) -> Void
  ) async throws -> SpeechAnalysisChannel {
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [
        transcriber
      ])
    else {
      throw TranscriberError.modelUnavailable
    }
    let analyzer = SpeechAnalyzer(modules: [transcriber])

    // Raw tap/engine buffers arrive here from the audio thread (bounded so a
    // slow converter drops audio rather than growing memory unbounded).
    let (rawStream, rawContinuation) = AsyncStream<AudioPCM.CopiedBuffer>.makeStream(
      bufferingPolicy: .bufferingNewest(64))
    let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()

    // Convert each raw buffer to the analyzer's required format on one task
    // (AVAudioConverter isn't thread-safe; keep it single-threaded here).
    let convertTask = Task.detached {
      var converter: AVAudioConverter?
      var converterInput: AVAudioFormat?
      for await copied in rawStream {
        let raw = copied.buffer
        if converter == nil || converterInput != raw.format {
          converter = AVAudioConverter(from: raw.format, to: analyzerFormat)
          converter?.primeMethod = .none
          converterInput = raw.format
        }
        guard let converter, let out = AudioPCM.convert(raw, with: converter, to: analyzerFormat)
        else { continue }
        inputContinuation.yield(AnalyzerInput(buffer: out))
      }
      inputContinuation.finish()
    }

    let resultsTask = Task {
      do {
        for try await result in transcriber.results {
          onResult(result)
        }
      } catch {
        AyrvoConsoleLog.live("\(speakerID) stream error — \(error.localizedDescription)")
      }
    }

    let analyzerTask = Task {
      do {
        if let last = try await analyzer.analyzeSequence(inputStream) {
          try await analyzer.finalizeAndFinish(through: last)
        } else {
          await analyzer.cancelAndFinishNow()
        }
      } catch {
        await analyzer.cancelAndFinishNow()
      }
    }

    return SpeechAnalysisChannel(
      speakerID: speakerID,
      rawContinuation: rawContinuation,
      tasks: [convertTask, resultsTask, analyzerTask])
  }

}
