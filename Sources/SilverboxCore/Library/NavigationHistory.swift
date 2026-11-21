import Foundation

/// The places a window showed, for Back and Forward as a browser has them.
/// The window says when it leaves a place; the history hands a place back
/// when the user goes back or forward, and passes over one that is gone.
nonisolated public struct NavigationHistory<Place: Equatable & Sendable>: Equatable, Sendable {
    /// The places before the one on show, the newest last.
    public private(set) var backPlaces: [Place] = []
    /// The places that Back left, the nearest last.
    public private(set) var forwardPlaces: [Place] = []
    /// How many places Back can reach; the oldest go first.
    public var limit: Int

    public init(limit: Int = 50) {
        self.limit = limit
    }

    /// The place Back would show, when it is still there.
    public var previous: Place? { backPlaces.last }

    /// Records the place that was just left for a new one. Nothing follows
    /// the new place, so the Forward list empties. A place left twice in a
    /// row is recorded once.
    public mutating func leave(_ place: Place) {
        if backPlaces.last != place { backPlaces.append(place) }
        if backPlaces.count > limit { backPlaces.removeFirst(backPlaces.count - limit) }
        forwardPlaces.removeAll()
    }

    public func canGoBack(where exists: (Place) -> Bool) -> Bool { backPlaces.contains(where: exists) }
    public func canGoForward(where exists: (Place) -> Bool) -> Bool { forwardPlaces.contains(where: exists) }

    /// The place before `current`, which goes on the Forward list. Places
    /// that no longer exist are dropped on the way. Nil when there is none;
    /// `current` then stays where it is.
    public mutating func goBack(from current: Place, where exists: (Place) -> Bool) -> Place? {
        Self.move(from: &backPlaces, to: &forwardPlaces, current: current, exists: exists)
    }

    /// The place that Back left last, with `current` back on the Back list.
    public mutating func goForward(from current: Place, where exists: (Place) -> Bool) -> Place? {
        Self.move(from: &forwardPlaces, to: &backPlaces, current: current, exists: exists)
    }

    private static func move(
        from source: inout [Place], to target: inout [Place], current: Place, exists: (Place) -> Bool
    ) -> Place? {
        while let place = source.popLast() {
            guard exists(place) else { continue }
            target.append(current)
            return place
        }
        return nil
    }
}
