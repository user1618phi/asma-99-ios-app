import AVFoundation
import Foundation
import Observation
import SwiftUI

/// Looping low-volume background ambience. Single instance owned by the app
/// for the whole tabbed-UI lifetime. Pause/resume is counter-based so the
/// pronunciation player, the speech recorder, and the reward sheet can each
/// request a pause independently without stepping on each other — the loop
/// only resumes once every outstanding reason has been cleared.
@MainActor
@Observable
final class AmbientSoundPlayer {
    static let shared = AmbientSoundPlayer()

    enum PauseReason: Hashable {
        /// Single-shot name pronunciation playback from `AudioPlayer`.
        case pronunciation
        /// User is on the Practice screen (for the whole lifetime of the view).
        case practice
        /// Speech recognizer's mic capture session is live.
        case recording
    }

    /// Currently selected ambience. Persisted to `UserDefaults`.
    private(set) var current: AmbientSound = .birds

    /// Active pause reasons. The loop is audible only when this is empty
    /// AND `current != .silent`.
    private(set) var pauseReasons: Set<PauseReason> = []

    /// Target unity-fraction volume. Deliberately quiet so the name audio
    /// always sits clearly on top.
    private let targetVolume: Float = 0.25

    private var player: AVAudioPlayer?
    private var fadeTimer: Timer?
    private var hasStarted = false

    private init() {
        if let raw = UserDefaults.standard.string(forKey: AppSettingsKey.ambientSound),
           let stored = AmbientSound(rawValue: raw) {
            current = stored
        }
    }

    // MARK: - Public API

    /// Begin (or resume) the ambient loop. Idempotent — safe to call on
    /// every `RootView.onAppear`.
    func start() {
        activatePlaybackSession()
        if !hasStarted {
            hasStarted = true
            UserDefaults.standard.set(current.rawValue, forKey: AppSettingsKey.ambientSound)
        }
        guard pauseReasons.isEmpty else { return }
        loadAndPlay(current)
    }

    /// Switch to a new sound. `.silent` stops playback but preserves the
    /// player state so a later selection re-engages quickly.
    func setSound(_ sound: AmbientSound) {
        guard sound != current else { return }
        current = sound
        UserDefaults.standard.set(sound.rawValue, forKey: AppSettingsKey.ambientSound)

        if sound == .silent {
            fadeOut { [weak self] in
                self?.player?.stop()
                self?.player = nil
            }
            return
        }

        if pauseReasons.isEmpty {
            activatePlaybackSession()
            loadAndPlay(sound)
        }
    }

    /// Add a pause reason. The loop fades out when the set transitions
    /// from empty → non-empty. Subsequent additions are no-ops audibly.
    func pause(reason: PauseReason) {
        let wasPlaying = pauseReasons.isEmpty
        pauseReasons.insert(reason)
        if wasPlaying {
            fadeOut { [weak self] in
                self?.player?.pause()
            }
        }
    }

    /// Clear a pause reason. The loop fades back in only when the last
    /// reason is removed.
    func resume(reason: PauseReason) {
        guard pauseReasons.contains(reason) else { return }
        pauseReasons.remove(reason)
        guard pauseReasons.isEmpty else { return }
        guard current != .silent else { return }
        // Pronunciation playback and the speech recorder both leave the
        // shared `AVAudioSession` in a category / activation state that
        // can't drive our looping player. Re-activate `.playback` every
        // time before nudging the player back to life.
        activatePlaybackSession()
        if player == nil {
            loadAndPlay(current)
        } else {
            player?.play()
            fadeIn()
        }
    }

    // MARK: - Internals

    /// Configure the shared audio session for low-volume looped playback
    /// that coexists with other audio. Called on every play/resume because
    /// `AudioPlayer` (`.spokenAudio`) and `SpeechScorer` (`.record`) both
    /// mutate the same session and leave it in non-playback states.
    private func activatePlaybackSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            #if DEBUG
            print("AmbientSoundPlayer session error: \(error)")
            #endif
        }
    }

    private func loadAndPlay(_ sound: AmbientSound) {
        guard let name = sound.fileName,
              let url = Bundle.main.url(forResource: name, withExtension: "mp3")
        else {
            player?.stop()
            player = nil
            return
        }

        // Same file already loaded — just play.
        if let existing = player, existing.url == url {
            existing.play()
            fadeIn()
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
            fadeIn()
        } catch {
            #if DEBUG
            print("AmbientSoundPlayer load error for \(name).mp3: \(error)")
            #endif
        }
    }

    private func fadeIn(duration: TimeInterval = 0.5) {
        guard let p = player else { return }
        runFade(from: p.volume, to: targetVolume, duration: duration, onComplete: nil)
    }

    private func fadeOut(duration: TimeInterval = 0.3, onComplete: (() -> Void)? = nil) {
        guard let p = player else {
            onComplete?()
            return
        }
        runFade(from: p.volume, to: 0, duration: duration, onComplete: onComplete)
    }

    private func runFade(
        from start: Float,
        to end: Float,
        duration: TimeInterval,
        onComplete: (() -> Void)?
    ) {
        fadeTimer?.invalidate()
        guard let p = player else {
            onComplete?()
            return
        }
        let steps = max(1, Int(duration * 30))
        let stepDuration = duration / Double(steps)
        var currentStep = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                currentStep += 1
                let progress = Float(currentStep) / Float(steps)
                p.volume = start + (end - start) * progress
                if currentStep >= steps {
                    timer.invalidate()
                    self.fadeTimer = nil
                    onComplete?()
                }
            }
        }
    }
}
