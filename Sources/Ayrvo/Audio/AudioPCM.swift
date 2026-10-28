import AVFoundation
import Foundation

enum AudioPCM {
  // The SDK cannot prove PCM ownership; only fresh deep copies enter the single-consumer stream.
  struct CopiedBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init?(_ source: AVAudioPCMBuffer) {
      guard let copy = AudioPCM.copy(source) else { return nil }
      buffer = copy
    }
  }

  /// Deep-copies a float PCM buffer (the only sample format the mic engine and
  /// the Core Audio tap deliver). Returns nil for empty or non-float buffers —
  /// live transcription simply skips those; the batch pass still has them.
  static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard buffer.frameLength > 0,
      let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
      let src = buffer.floatChannelData, let dst = out.floatChannelData
    else { return nil }
    out.frameLength = buffer.frameLength
    let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
    for ch in 0..<Int(buffer.format.channelCount) { memcpy(dst[ch], src[ch], bytes) }
    return out
  }

  static func convert(
    _ input: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / input.format.sampleRate
    let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64
    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    var fed = false
    var error: NSError?
    let status = converter.convert(to: out, error: &error) { _, outStatus in
      if fed {
        outStatus.pointee = .noDataNow
        return nil
      }
      fed = true
      outStatus.pointee = .haveData
      return input
    }
    return (status != .error && out.frameLength > 0) ? out : nil
  }
}
