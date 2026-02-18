import AVFoundation
import CoreMedia
import ExpoModulesCore
import ReplayKit

private enum RecorderState: String {
  case idle
  case recording
  case stopping
}

public class ExpoReplaykitRecorderModule: Module {
  private let recorder = RPScreenRecorder.shared()
  private let writerQueue = DispatchQueue(label: "expo.replaykit.recorder.writer")

  private var recorderState: RecorderState = .idle
  private var assetWriter: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var micAudioInput: AVAssetWriterInput?
  private var appAudioInput: AVAssetWriterInput?
  private var outputURL: URL?
  private var firstSampleTimestamp: CMTime?
  private var recordingStartDate: Date?
  private var recordingEndDate: Date?
  private var includeMicAudio = true
  private var includeAppAudio = true

  public func definition() -> ModuleDefinition {
    Name("ExpoReplaykitRecorder")

    AsyncFunction("isAvailable") { () -> Bool in
      return self.recorder.isAvailable
    }

    Function("getState") { () -> [String: String] in
      return ["state": self.recorderState.rawValue]
    }

    AsyncFunction("startRecording") { (options: [String: Any]?, promise: Promise) in
      self.startRecording(options: options, promise: promise)
    }

    AsyncFunction("stopRecording") { (promise: Promise) in
      self.stopRecording(promise: promise)
    }

    AsyncFunction("cancelRecording") { (promise: Promise) in
      self.cancelRecording(promise: promise)
    }
  }

  private func startRecording(options: [String: Any]?, promise: Promise) {
    if recorderState != .idle {
      promise.reject("ERR_RECORDER_BUSY", "A screen recording is already in progress")
      return
    }

    guard recorder.isAvailable else {
      promise.reject("ERR_RECORDER_UNAVAILABLE", "ReplayKit recorder is not available on this device")
      return
    }

    includeMicAudio = options?["mic"] as? Bool ?? true
    includeAppAudio = options?["appAudio"] as? Bool ?? true

    do {
      try prepareAssetWriter()
    } catch {
      promise.reject("ERR_RECORDER_PREPARE_FAILED", "Failed to prepare output writer: \(error.localizedDescription)")
      resetState(deleteOutputFile: true)
      return
    }

    recorderState = .recording
    recordingStartDate = Date()
    recordingEndDate = nil
    recorder.isMicrophoneEnabled = includeMicAudio

    recorder.startCapture(handler: { [weak self] sampleBuffer, sampleType, error in
      guard let self = self else { return }
      if let error = error {
        self.writerQueue.async {
          self.recorderState = .idle
          self.resetState(deleteOutputFile: true)
        }
        return
      }
      self.append(sampleBuffer: sampleBuffer, sampleType: sampleType)
    }, completionHandler: { [weak self] error in
      guard let self = self else { return }
      if let error = error {
        self.recorderState = .idle
        self.resetState(deleteOutputFile: true)
        promise.reject("ERR_RECORDER_START_FAILED", "ReplayKit could not start capture: \(error.localizedDescription)")
        return
      }
      promise.resolve(nil)
    })
  }

  private func stopRecording(promise: Promise) {
    guard recorderState == .recording else {
      promise.reject("ERR_RECORDER_NOT_RUNNING", "No screen recording is currently in progress")
      return
    }

    recorderState = .stopping
    recordingEndDate = Date()

    recorder.stopCapture { [weak self] error in
      guard let self = self else { return }
      if let error = error {
        self.recorderState = .idle
        self.resetState(deleteOutputFile: true)
        promise.reject("ERR_RECORDER_STOP_FAILED", "Failed to stop ReplayKit capture: \(error.localizedDescription)")
        return
      }

      self.writerQueue.async {
        self.videoInput?.markAsFinished()
        self.micAudioInput?.markAsFinished()
        self.appAudioInput?.markAsFinished()

        guard let writer = self.assetWriter, let outputURL = self.outputURL else {
          self.recorderState = .idle
          self.resetState(deleteOutputFile: true)
          promise.reject("ERR_RECORDER_MISSING_WRITER", "Recording writer was unavailable while stopping capture")
          return
        }

        writer.finishWriting {
          let status = writer.status
          if status != .completed {
            let writerError = writer.error
            self.recorderState = .idle
            self.resetState(deleteOutputFile: true)
            promise.reject("ERR_RECORDER_WRITE_FAILED", "Failed to finalize captured recording")
            return
          }

          let startedAtMs = Int((self.recordingStartDate?.timeIntervalSince1970 ?? 0) * 1000)
          let endedAtMs = Int((self.recordingEndDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000)
          let durationSeconds = max(0, Double(endedAtMs - startedAtMs) / 1000.0)

          self.recorderState = .idle
          self.resetState(deleteOutputFile: false)
          promise.resolve([
            "uri": outputURL.absoluteString,
            "durationSeconds": durationSeconds,
            "startedAtMs": startedAtMs,
            "endedAtMs": endedAtMs,
          ])
        }
      }
    }
  }

  private func cancelRecording(promise: Promise) {
    guard recorderState == .recording || recorderState == .stopping else {
      promise.resolve(false)
      return
    }

    recorderState = .stopping

    recorder.stopCapture { [weak self] _ in
      guard let self = self else { return }
      self.recorderState = .idle
      self.resetState(deleteOutputFile: true)
      promise.resolve(true)
    }
  }

  private func prepareAssetWriter() throws {
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let filename = "replaykit-\(Int(Date().timeIntervalSince1970 * 1000)).mp4"
    let outputURL = directory.appendingPathComponent(filename)

    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

    let screenBounds = UIScreen.main.bounds
    let screenScale = UIScreen.main.scale
    let width = Int(screenBounds.width * screenScale)
    let height = Int(screenBounds.height * screenScale)

    let compressionSettings: [String: Any] = [
      AVVideoAverageBitRateKey: 10_000_000,
      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ]

    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: compressionSettings,
    ]

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = true
    if writer.canAdd(videoInput) {
      writer.add(videoInput)
    }

    let audioSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVNumberOfChannelsKey: 2,
      AVSampleRateKey: 44_100,
      AVEncoderBitRateKey: 128_000,
    ]

    var micInput: AVAssetWriterInput?
    if includeMicAudio {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      input.expectsMediaDataInRealTime = true
      if writer.canAdd(input) {
        writer.add(input)
        micInput = input
      }
    }

    var appInput: AVAssetWriterInput?
    if includeAppAudio {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      input.expectsMediaDataInRealTime = true
      if writer.canAdd(input) {
        writer.add(input)
        appInput = input
      }
    }

    if !writer.startWriting() {
      throw NSError(domain: "ExpoReplaykitRecorder", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Asset writer failed to start"])
    }

    self.assetWriter = writer
    self.videoInput = videoInput
    self.micAudioInput = micInput
    self.appAudioInput = appInput
    self.outputURL = outputURL
    self.firstSampleTimestamp = nil
  }

  private func append(sampleBuffer: CMSampleBuffer, sampleType: RPSampleBufferType) {
    guard recorderState == .recording else { return }
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

    writerQueue.async {
      guard self.recorderState == .recording else { return }
      guard let writer = self.assetWriter else { return }

      if self.firstSampleTimestamp == nil {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.firstSampleTimestamp = timestamp
        writer.startSession(atSourceTime: timestamp)
      }

      switch sampleType {
      case .video:
        if let input = self.videoInput, input.isReadyForMoreMediaData {
          input.append(sampleBuffer)
        }
      case .audioMic:
        if self.includeMicAudio, let input = self.micAudioInput, input.isReadyForMoreMediaData {
          input.append(sampleBuffer)
        }
      case .audioApp:
        if self.includeAppAudio, let input = self.appAudioInput, input.isReadyForMoreMediaData {
          input.append(sampleBuffer)
        }
      @unknown default:
        break
      }
    }
  }

  private func resetState(deleteOutputFile: Bool) {
    let urlToDelete = outputURL

    assetWriter = nil
    videoInput = nil
    micAudioInput = nil
    appAudioInput = nil
    outputURL = nil
    firstSampleTimestamp = nil
    recordingStartDate = nil
    recordingEndDate = nil

    if deleteOutputFile, let fileURL = urlToDelete {
      try? FileManager.default.removeItem(at: fileURL)
    }
  }
}
