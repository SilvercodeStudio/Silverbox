import Foundation

/// Global launch preferences that eXoMAC layers over each game's config,
/// the way eXoDOS layers `options.conf` over `dosbox.conf`.
nonisolated public struct LaunchOptions: Hashable, Sendable, Codable {
    nonisolated public enum WindowSize: String, CaseIterable, Sendable, Codable, Identifiable {
        case `default`, small, medium, large
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .default: return "Emulator default"
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    nonisolated public enum AspectMode: String, CaseIterable, Sendable, Codable, Identifiable {
        case gameConfig, on, off
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .gameConfig: return "As configured per game"
            case .on: return "Always on"
            case .off: return "Always off"
            }
        }
    }

    /// DOSBox Staging shader presets.
    nonisolated public enum Shader: String, CaseIterable, Sendable, Codable, Identifiable {
        case crtAuto = "crt-auto"
        case crtAutoMachine = "crt-auto-machine"
        case sharp
        case bilinear
        case none
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .crtAuto: return "CRT (auto)"
            case .crtAutoMachine: return "CRT (match machine)"
            case .sharp: return "Sharp pixels"
            case .bilinear: return "Bilinear"
            case .none: return "None"
            }
        }
    }

    /// How General MIDI music is rendered when a game asks for the host's
    /// default MIDI device.
    nonisolated public enum GeneralMIDI: String, CaseIterable, Sendable, Codable, Identifiable {
        case automatic
        case fluidSynthSoundCanvas
        case coreAudio
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .automatic: return "Automatic (FluidSynth when available)"
            case .fluidSynthSoundCanvas: return "FluidSynth with the eXoDOS Sound Canvas SoundFont"
            case .coreAudio: return "macOS built-in synthesizer"
            }
        }
    }

    public var fullscreen: Bool
    public var windowSize: WindowSize
    public var aspect: AspectMode
    public var shader: Shader
    public var generalMIDI: GeneralMIDI
    public var quietStartup: Bool

    public init(fullscreen: Bool = false, windowSize: WindowSize = .default, aspect: AspectMode = .gameConfig,
                shader: Shader = .crtAuto, generalMIDI: GeneralMIDI = .automatic, quietStartup: Bool = true) {
        self.fullscreen = fullscreen
        self.windowSize = windowSize
        self.aspect = aspect
        self.shader = shader
        self.generalMIDI = generalMIDI
        self.quietStartup = quietStartup
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fullscreen = try c.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? false
        windowSize = try c.decodeIfPresent(WindowSize.self, forKey: .windowSize) ?? .default
        aspect = try c.decodeIfPresent(AspectMode.self, forKey: .aspect) ?? .gameConfig
        shader = try c.decodeIfPresent(Shader.self, forKey: .shader) ?? .crtAuto
        generalMIDI = try c.decodeIfPresent(GeneralMIDI.self, forKey: .generalMIDI) ?? .automatic
        quietStartup = try c.decodeIfPresent(Bool.self, forKey: .quietStartup) ?? true
    }
}

/// Per-game choices that replace the global ``LaunchOptions`` fields.
nonisolated public struct LaunchOverrides: Hashable, Sendable, Codable {
    public var fullscreen: Bool?
    public var windowSize: LaunchOptions.WindowSize?
    public var aspect: LaunchOptions.AspectMode?
    public var shader: LaunchOptions.Shader?

    public init(fullscreen: Bool? = nil, windowSize: LaunchOptions.WindowSize? = nil,
                aspect: LaunchOptions.AspectMode? = nil, shader: LaunchOptions.Shader? = nil) {
        self.fullscreen = fullscreen
        self.windowSize = windowSize
        self.aspect = aspect
        self.shader = shader
    }

    public var isEmpty: Bool {
        fullscreen == nil && windowSize == nil && aspect == nil && shader == nil
    }

    /// The overrides needed to turn `base` into `chosen`.
    public init(base: LaunchOptions, chosen: LaunchOptions) {
        fullscreen = chosen.fullscreen == base.fullscreen ? nil : chosen.fullscreen
        windowSize = chosen.windowSize == base.windowSize ? nil : chosen.windowSize
        aspect = chosen.aspect == base.aspect ? nil : chosen.aspect
        shader = chosen.shader == base.shader ? nil : chosen.shader
    }
}

nonisolated extension LaunchOptions {
    public func applying(_ overrides: LaunchOverrides?) -> LaunchOptions {
        guard let overrides else { return self }
        var result = self
        if let value = overrides.fullscreen { result.fullscreen = value }
        if let value = overrides.windowSize { result.windowSize = value }
        if let value = overrides.aspect { result.aspect = value }
        if let value = overrides.shader { result.shader = value }
        return result
    }
}
