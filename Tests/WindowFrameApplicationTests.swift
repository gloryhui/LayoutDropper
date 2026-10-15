import Cocoa
import ApplicationServices

@main
enum WindowFrameApplicationTests {
    static let target = CGRect(x: 1600, y: 24, width: 1400, height: 1000)

    static func main() {
        let normal = WindowFixture(target: target)
        normal.application.start()
        precondition(normal.writes.isEmpty, "Wait for mouse-up before writing")
        normal.drain()
        precondition(normal.writes == ["position", "size", "position"])
        precondition(normal.delays == [0.05, 0.10, 0.15])
        precondition(normal.succeeded && normal.completions == 1)

        let crossing = WindowFixture(target: target)
        crossing.sizeHandler = { fixture, size in
            // The first request is still constrained by the old display while its
            // move is being processed; a subsequent request can use the new width.
            fixture.actual?.size = CGSize(width: fixture.sizeWrites == 1 ? 900 : size.width,
                                          height: size.height)
            return .success
        }
        crossing.application.start()
        crossing.drain()
        precondition(crossing.succeeded && crossing.sizeWrites == 2,
                     "Reapply a size clamped during a display transition")

        let lateDrag = WindowFixture(target: target)
        lateDrag.application.start()
        lateDrag.next() // initial writes
        lateDrag.next() // first read reports success
        precondition(lateDrag.completions == 0)
        lateDrag.actual = CGRect(x: 100, y: 100, width: 700, height: 500)
        lateDrag.drain()
        precondition(lateDrag.succeeded && lateDrag.sizeWrites == 2,
                     "Recover when a late native drag/tiling update overwrites the frame")

        let transient = WindowFixture(target: target)
        transient.sizeHandler = { fixture, size in
            if fixture.sizeWrites == 1 { return .cannotComplete }
            fixture.actual?.size = size
            return .success
        }
        transient.application.start()
        transient.drain()
        precondition(transient.succeeded && transient.sizeWrites == 2)
        precondition(transient.errors == [.cannotComplete], "Keep AX error diagnostics")

        let minimumSize = WindowFixture(target: target)
        minimumSize.sizeHandler = { fixture, size in
            fixture.actual?.size = CGSize(width: size.width + 200, height: size.height)
            return .success
        }
        minimumSize.application.start()
        minimumSize.drain()
        precondition(!minimumSize.succeeded && minimumSize.completions == 1)
        precondition(minimumSize.sizeWrites == 5,
                     "An application size constraint must not cause unlimited retries")

        let unavailable = WindowFixture(target: target)
        unavailable.actual = nil
        unavailable.sizeHandler = { _, _ in .invalidUIElement }
        unavailable.application.start()
        unavailable.drain()
        precondition(!unavailable.succeeded && unavailable.completions == 1)
        precondition(unavailable.sizeWrites == 5 && unavailable.errors.contains(.invalidUIElement))

        let cancelledBeforeStart = WindowFixture(target: target)
        cancelledBeforeStart.application.start()
        cancelledBeforeStart.application.cancel()
        cancelledBeforeStart.drain()
        precondition(cancelledBeforeStart.writes.isEmpty && cancelledBeforeStart.completions == 0)

        let cancelledDuringRetry = WindowFixture(target: target)
        cancelledDuringRetry.application.start()
        cancelledDuringRetry.next()
        cancelledDuringRetry.application.cancel()
        cancelledDuringRetry.actual = .zero // a new user drag owns the window now
        cancelledDuringRetry.drain()
        precondition(cancelledDuringRetry.writes.count == 3 && cancelledDuringRetry.actual == .zero)
        precondition(cancelledDuringRetry.completions == 0)

        precondition(WindowFrameApplication.matches(target.offsetBy(dx: 0.5, dy: -0.5), target: target))
        precondition(!WindowFrameApplication.matches(target.offsetBy(dx: 2, dy: 0), target: target))
        precondition(!WindowFrameApplication.matches(nil, target: target))
        print("Window frame recovery passed: display clamping, late overwrite, AX errors, bounded constraints, cancellation and rounding tolerance (simulated AX).")
    }
}

private final class WindowFixture {
    let target: CGRect
    var actual: CGRect? = CGRect(x: 50, y: 50, width: 700, height: 500)
    var writes: [String] = []
    var sizeWrites = 0
    var delays: [TimeInterval] = []
    var jobs: [() -> Void] = []
    var sizeHandler: ((WindowFixture, CGSize) -> AXError)?
    var completions = 0
    var succeeded = false
    var errors: [AXError] = []
    lazy var application = WindowFrameApplication(
        target: target,
        readFrame: { [unowned self] in actual },
        setPosition: { [unowned self] point in
            writes.append("position")
            actual?.origin = point
            return actual == nil ? .invalidUIElement : .success
        },
        setSize: { [unowned self] size in
            writes.append("size")
            sizeWrites += 1
            if let sizeHandler { return sizeHandler(self, size) }
            actual?.size = size
            return .success
        },
        schedule: { [unowned self] delay, job in
            delays.append(delay)
            jobs.append(job)
        },
        completion: { [unowned self] frame, errors in
            completions += 1
            succeeded = WindowFrameApplication.matches(frame, target: target)
            self.errors = errors
        }
    )

    init(target: CGRect) { self.target = target }

    func next() {
        precondition(!jobs.isEmpty)
        jobs.removeFirst()()
    }

    func drain() {
        var count = 0
        while !jobs.isEmpty {
            count += 1
            precondition(count < 100, "Retry loop must be bounded")
            next()
        }
    }
}
