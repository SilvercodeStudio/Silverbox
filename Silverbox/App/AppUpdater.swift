import AppKit

#if canImport(Sparkle)
    import Sparkle
#endif

/// Updates through Sparkle, in a build that `make dist` made (`SilverboxArchive` in Info.plist):
/// a build from source never replaces itself with a released one. Info.plist has the feed and its
/// key. The app decides when an update that is ready may relaunch it (`AppModel.postponeRelaunch`).
///
/// Without the Sparkle package (a checkout before it was added in Xcode), the app builds with no
/// updater; `make dist` refuses such a build.
@Observable
final class AppUpdater: NSObject {
    #if canImport(Sparkle)
        /// Nil in a build from source.
        @ObservationIgnored private var controller: SPUStandardUpdaterController?
        @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    #endif
    /// Returns true to hold the relaunch, and then calls its argument to install.
    @ObservationIgnored private let postponeRelaunch: (@escaping () -> Void) -> Bool

    /// False in a build from source, which has no Check for Updates.
    var isAvailable: Bool {
        #if canImport(Sparkle)
            controller != nil
        #else
            false
        #endif
    }
    /// False while Sparkle already checks, downloads, or shows an update.
    private(set) var canCheckForUpdates = false
    /// Sparkle asks at the second launch whether to check by itself; Settings › General changes it.
    /// Sparkle keeps it in the app's defaults.
    var checksAutomatically = false {
        didSet {
            #if canImport(Sparkle)
                guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != checksAutomatically
                else { return }
                updater.automaticallyChecksForUpdates = checksAutomatically
            #endif
        }
    }

    init(postponeRelaunch: @escaping (@escaping () -> Void) -> Bool) {
        self.postponeRelaunch = postponeRelaunch
        super.init()
        #if canImport(Sparkle)
            guard AppInfo.isArchive else { return }
            let controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            // Sparkle changes these on the main thread.
            observations = [
                controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                    MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
                },
                controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) {
                    [weak self] updater, _ in
                    MainActor.assumeIsolated { self?.checksAutomatically = updater.automaticallyChecksForUpdates }
                },
            ]
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
            controller?.checkForUpdates(nil)
        #endif
    }
}

#if canImport(Sparkle)
    extension AppUpdater: SPUUpdaterDelegate {
        func updater(
            _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
            untilInvokingBlock installHandler: @escaping () -> Void
        ) -> Bool {
            postponeRelaunch(installHandler)
        }
    }
#endif
