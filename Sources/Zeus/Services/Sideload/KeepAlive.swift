import Foundation
import AVFoundation

/// Keeps Zeus running while it's backgrounded, so the loopback OTA server stays
/// alive while the user is in Safari / Settings (trust + enroll) and while
/// installd fetches the build. A sandboxed app is otherwise suspended the
/// instant it backgrounds — which kills the server and produces
/// "cannot connect to 127.0.0.1".
///
/// The mechanism is a looping *silent* audio buffer under the `audio` background
/// mode (mixed with others so it never interrupts the user's music). This is the
/// standard local-server keep-alive trick — fine for a personal/TestFlight build.
final class KeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var running = false

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else { return }
            buffer.frameLength = buffer.frameCapacity   // zero-filled → silence

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        running = false
    }
}
