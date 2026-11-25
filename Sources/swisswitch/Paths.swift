import Foundation

extension URL {
    /// A file under `~/Library/Application Support/swisswitch/`, or the path in the
    /// environment variable `override` when it's set.
    static func swisswitchSupportFile(_ relativePath: String, override: String) -> URL {
        if let path = ProcessInfo.processInfo.environment[override] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "swisswitch/\(relativePath)")
    }
}
