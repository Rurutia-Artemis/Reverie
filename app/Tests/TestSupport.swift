import Foundation

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message). expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func expectTrue(_ value: Bool, _ message: String) {
    if !value {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func expectFalse(_ value: Bool, _ message: String) {
    if value {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
