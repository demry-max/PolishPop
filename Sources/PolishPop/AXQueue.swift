import Foundation
@preconcurrency import ApplicationServices

/// Carries an `AXUIElement` across concurrency domains.
///
/// Accessibility elements are CoreFoundation objects that the API allows any thread to use, but
/// they carry no `Sendable` conformance, so the unchecked box is the honest way to say so.
struct AXElementBox: @unchecked Sendable {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }
}

/// Runs Accessibility queries on a dedicated serial queue.
///
/// Every `AXUIElementCopyAttributeValue` blocks the calling thread until the target application
/// answers or the messaging timeout expires. Doing that on the main thread — which the selection
/// monitor previously did after every single click — stalls the cursor and every window in
/// PolishPop for as long as the slowest app takes to reply.
final class AXQueue: @unchecked Sendable {
    static let shared = AXQueue()

    private let queue = DispatchQueue(label: "com.demry.polishpop.accessibility", qos: .userInitiated)

    private init() {}

    func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }
}
