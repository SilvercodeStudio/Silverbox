import Foundation

/// The web pages that the app links to.
nonisolated public enum SilverboxLinks {
    /// The website: Help › Silverbox Website, and the About window's Website.
    public static let website = URL(string: "https://getsilverbox.app")!

    /// The studio that makes Silverbox, and its other apps: the link after the About window's
    /// copyright.
    public static let studio = URL(string: "https://silvercode.studio")!

    /// The studio's page for a tip: Help › Support Silverbox and the About window's Leave a Tip.
    /// The page ignores `from` today; it is there so that a later page can choose Silverbox, or
    /// count where visitors come from, also for older versions.
    public static let sponsor = URL(string: "https://silvercode.studio/sponsor?from=silverbox")!
}
