import AVFoundation
import Foundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayer()

    @Published private(set) var currentlyPlayingFile: String?

    private var player: AVAudioPlayer?

    func play(file: String) {
        let parts = file.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1]))
        else {
            assertionFailure("Audio file not found in bundle: \(file)")
            return
        }
        // Silence the ambient loop before we change the session category —
        // otherwise the swap to `.spokenAudio` cuts the ambience abruptly.
        AmbientSoundPlayer.shared.pause(reason: .pronunciation)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            currentlyPlayingFile = file
        } catch {
            print("AudioPlayer error: \(error)")
            currentlyPlayingFile = nil
            AmbientSoundPlayer.shared.resume(reason: .pronunciation)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentlyPlayingFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        AmbientSoundPlayer.shared.resume(reason: .pronunciation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.currentlyPlayingFile = nil
            self.player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            AmbientSoundPlayer.shared.resume(reason: .pronunciation)
        }
    }
}
