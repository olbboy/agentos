import Foundation
import CoreServices

/// Watches the agents' skill folders with FSEvents.
/// Debounced by a 1.0s latency plus FSEvents' own coalescing (planned risk: a burst
/// of events during a large sync → the UI must not stutter).
final class FsEventsWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    var onChange: (@Sendable () -> Void)?

    func start(paths: [String]) {
        stop()
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FsEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange?()
        }
        stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency: gom event trong 1s
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
