import AppKit
import Foundation
import NetFS
import SilverboxCore

/// Network shares that hold collections or the local data folder: how to
/// connect to them again when they are not mounted.
extension AppModel {
    /// The places Silverbox reads from a volume: each enabled collection,
    /// its download, and the local data folder.
    var volumePlaces: [URL] {
        settings.enabledCollections.flatMap { collection in
            [collection.rootURL] + [collection.downloadPath].compactMap { $0 }.map { URL(fileURLWithPath: $0) }
        } + [settings.localStorePath].compactMap { $0 }.map { URL(fileURLWithPath: $0) }
    }

    /// `/Volumes/<name>` for a path on a volume other than the startup disk.
    static func mountPoint(of url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return nil }
        return "/Volumes/" + parts[2]
    }

    /// Notes how to mount each network share that holds a place Silverbox
    /// reads, as macOS reports it while mounted (`smb://user@server/share`),
    /// so Try Again can connect to it when it is gone.
    func recordRemountURLs() {
        var urls = settings.remountURLs
        for place in volumePlaces {
            guard let mountPoint = Self.mountPoint(of: place), !Self.volumeIsMissing(for: place),
                let remount = try? place.resourceValues(forKeys: [.volumeURLForRemountingKey]).volumeURLForRemounting
            else { continue }
            urls[mountPoint] = remount.absoluteString
        }
        if urls != settings.remountURLs { settings.remountURLs = urls }
    }

    /// The network shares that hold a place Silverbox reads, are not mounted
    /// now, and can be connected to again.
    var disconnectedShares: [URL] {
        var seen: Set<String> = []
        return volumePlaces.compactMap { place in
            guard Self.volumeIsMissing(for: place), let mountPoint = Self.mountPoint(of: place),
                seen.insert(mountPoint).inserted, let string = settings.remountURLs[mountPoint]
            else { return nil }
            return URL(string: string)
        }
    }

    /// Connects to the network shares that are gone, as the Finder's Connect
    /// to Server does (asking for a password only when the Keychain has
    /// none), then loads the library again. Without such shares it only
    /// loads again.
    func tryAgain() {
        let shares = disconnectedShares
        guard !shares.isEmpty else {
            reloadLibrary()
            return
        }
        for share in shares { connect(to: share) }
    }

    /// Mounts `share` in /Volumes. The mount's notification loads the
    /// library again (`volumeChanged`); a failure says why.
    private func connect(to share: URL) {
        let options = NSMutableDictionary()
        options[kNAUIOptionKey] = kNAUIOptionAllowUI
        var request: AsyncRequestID?
        let name = share.lastPathComponent.removingPercentEncoding ?? share.lastPathComponent
        let host = share.host ?? ""
        let status = NetFSMountURLAsync(share as CFURL, nil, nil, nil, options, nil, &request, .main) {
            status, _, _ in
            MainActor.assumeIsolated { [weak self] in
                self?.connectFinished(status: status, name: name, host: host)
            }
        }
        if status != 0 { connectFinished(status: status, name: name, host: host) }
    }

    private func connectFinished(status: Int32, name: String, host: String) {
        // ECANCELED: the user closed the password dialog.
        guard status != 0, status != ECANCELED else { return }
        let reason =
            status > 0
            ? String(cString: strerror(status)) : "The server answered with error \(status)."
        alert = AppAlert(
            title: "Could not connect to \(name)",
            message: "\(reason) Check that \(host.isEmpty ? "the server" : host) is on and on the network.")
    }
}
