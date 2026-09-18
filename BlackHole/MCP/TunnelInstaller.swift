import CryptoKit
import Foundation

/// Fetches the Cloudflare tunnel client on demand, so turning on public access needs no Homebrew
/// and no Terminal. The download is pinned to one release and checked against its SHA-256.
enum TunnelInstaller {
    static let version = "2026.9.1"
    private static let sha256 = "c27ab8fd0aa489449e3d201eb02f957ef460a13b613662928b1b23394bf1bcfe"
    private static var downloadURL: URL {
        URL(string: "https://github.com/cloudflare/cloudflared/releases/download/\(version)/cloudflared-darwin-arm64.tgz")!
    }

    /// Where Black Hole keeps its own copy.
    static var managedBinary: URL {
        URL.applicationSupportDirectory.appending(path: "Black Hole/bin/cloudflared")
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: managedBinary.path)
    }

    enum InstallError: LocalizedError {
        case download(String)
        case checksumMismatch
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .download(let reason): "Couldn't download the tunnel: \(reason)"
            case .checksumMismatch: "The downloaded tunnel didn't match its checksum."
            case .extractionFailed: "Couldn't unpack the tunnel."
            }
        }
    }

    /// Downloads, verifies and unpacks the binary. Reports 0...1 progress.
    static func install(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if isInstalled { return managedBinary }

        let (tempFile, response) = try await URLSession.shared.download(from: downloadURL, delegate: nil)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.download("HTTP \(http.statusCode)")
        }
        progress(0.7)

        let data = try Data(contentsOf: tempFile, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw InstallError.checksumMismatch }
        progress(0.85)

        let binDirectory = managedBinary.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", tempFile.path, "-C", binDirectory.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0, FileManager.default.fileExists(atPath: managedBinary.path) else {
            throw InstallError.extractionFailed
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedBinary.path)
        progress(1)
        return managedBinary
    }
}
