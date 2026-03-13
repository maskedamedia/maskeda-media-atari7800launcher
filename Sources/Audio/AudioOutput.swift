import AVFoundation
import Foundation

public final class AudioOutput: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "AudioOutput.queue")
    private var currentSampleRate: Double = 48_000
    private var format: AVAudioFormat?
    private var started = false

    public init() {}

    public func configure(sampleRate: Double) {
        queue.sync {
            let nextRate = sampleRate > 0 ? sampleRate : 48_000
            guard format == nil || abs(currentSampleRate - nextRate) > 0.5 else {
                startIfNeeded()
                return
            }

            currentSampleRate = nextRate
            format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: currentSampleRate, channels: 2, interleaved: true)

            engine.stop()
            engine.reset()
            if engine.attachedNodes.contains(player) == false {
                engine.attach(player)
            }
            if let format {
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            try? engine.start()
            startIfNeeded()
        }
    }

    public func enqueue(samples: UnsafePointer<Int16>, frameCount: Int) {
        guard frameCount > 0 else {
            return
        }

        let sampleCopy = Array(UnsafeBufferPointer(start: samples, count: frameCount * 2))

        queue.async {
            self.startIfNeeded()
            guard let format = self.format else {
                return
            }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
                return
            }

            buffer.frameLength = AVAudioFrameCount(frameCount)
            sampleCopy.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else {
                    return
                }
                buffer.int16ChannelData?.pointee.update(from: baseAddress, count: frameCount * 2)
            }
            self.player.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    public func stop() {
        queue.sync {
            player.stop()
            engine.stop()
            started = false
        }
    }

    private func startIfNeeded() {
        if engine.isRunning == false {
            try? engine.start()
        }
        if started == false {
            player.play()
            started = true
        }
    }
}
