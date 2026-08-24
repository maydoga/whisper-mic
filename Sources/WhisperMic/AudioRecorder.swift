import AVFoundation
import Foundation

enum AudioRecorderError: Error, LocalizedError {
    case microphoneUnavailable
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            return "Microphone not available. Check System Settings > Privacy > Microphone."
        case .recordingFailed(let msg):
            return "Recording failed: \(msg)"
        }
    }
}

final class AudioRecorder {
    var isRecording = false
    var recordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?

    /// `language` is baked into the filename so a retry days later still uses
    /// the language that was selected when you spoke.
    func startRecording(language: String) throws {
        let url = RecordingStore.newRecordingURL(language: language)
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw AudioRecorderError.recordingFailed("AVAudioRecorder.record() returned false")
            }
            audioRecorder = recorder
            isRecording = true
            recordingDuration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingDuration += 0.1
            }
        } catch let error as AudioRecorderError {
            throw error
        } catch {
            throw AudioRecorderError.recordingFailed(error.localizedDescription)
        }
    }

    func stopRecording() -> Recording? {
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        isRecording = false
        let url = recordingURL
        recordingURL = nil
        audioRecorder = nil
        return url.flatMap(Recording.init(url:))
    }
}
