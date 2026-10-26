import Foundation
import Testing

@testable import eXoCore

@Suite("MIDI batch patcher")
struct MIDIBatchPatcherTests {
    static let batch =
        "@echo off\r\nif errorlevel = 1 goto GM\r\n:GM\r\nCONFIG -set \"mididevice=default\"\r\ngoto end\r\n:MT\r\nCONFIG -set \"mididevice=mt32\"\r\n:end\r\n"

    @Test func rewritesDefaultAndKeepsTheRest() throws {
        let rewritten = try #require(MIDIBatchPatcher.rewrite(Self.batch, device: "coreaudio"))
        #expect(
            rewritten.contains(
                "rem Silverbox replaced: CONFIG -set \"mididevice=default\"\r\nCONFIG -set \"mididevice=coreaudio\"\r\n"
            ))
        #expect(rewritten.contains("CONFIG -set \"mididevice=mt32\"\r\n"))
        #expect(rewritten.hasPrefix("@echo off\r\n"))
        // The second pass with another device rewrites our own line, not the note.
        let again = try #require(MIDIBatchPatcher.rewrite(rewritten, device: "fluidsynth"))
        #expect(
            again.contains("replaced: CONFIG -set \"mididevice=default\"\r\nCONFIG -set \"mididevice=fluidsynth\"\r\n"))
        #expect(!again.contains("coreaudio"))
        // Nothing to change: nil.
        #expect(MIDIBatchPatcher.rewrite(again, device: "fluidsynth") == nil)
        #expect(MIDIBatchPatcher.rewrite("@echo off\r\nrun.exe\r\n", device: "coreaudio") == nil)
        #expect(MIDIBatchPatcher.setsDefaultDevice("config -set mididevice=default"))
        #expect(!MIDIBatchPatcher.setsDefaultDevice("CONFIG -set \"mididevice=mt32\""))
    }

    @Test func writesPatchesInPlaceOrIntoTheOverlay() throws {
        let fm = FileManager.default
        let scratch = try FixtureLibrary.scratchDirectory().appendingPathComponent("midipatch-\(UUID().uuidString)")
        let games = scratch.appendingPathComponent("eXo/eXoDOS", isDirectory: true)
        let game = games.appendingPathComponent("ultima4", isDirectory: true)
        try fm.createDirectory(at: game.appendingPathComponent("upgrade"), withIntermediateDirectories: true)
        try Self.batch.data(using: .isoLatin1)!.write(to: game.appendingPathComponent("upgrade/run.bat"))
        try "@echo off\r\nrun\r\n".write(to: game.appendingPathComponent("run.bat"), atomically: true, encoding: .utf8)

        let inPlace = MIDIBatchPatcher.patches(gameFolder: game, overlay: nil, device: "coreaudio")
        #expect(inPlace.map(\.destination.lastPathComponent) == ["run.bat"])
        #expect(inPlace.first?.destination.path.hasSuffix("ultima4/upgrade/run.bat") == true)

        let overlayDirectory = scratch.appendingPathComponent("Overlay/eXoDOS", isDirectory: true)
        let overlay = OverlayMount(base: games, directory: overlayDirectory)
        let patches = MIDIBatchPatcher.patches(gameFolder: game, overlay: overlay, device: "fluidsynth")
        let destination = try #require(patches.first?.destination)
        #expect(destination.path == overlayDirectory.appendingPathComponent("ultima4/upgrade/run.bat").path)
        try patches.forEach { try $0.write() }
        let written = try #require(String(data: Data(contentsOf: destination), encoding: .isoLatin1))
        #expect(written.contains("CONFIG -set \"mididevice=fluidsynth\""))
        // The original was left alone.
        #expect(
            try Data(contentsOf: game.appendingPathComponent("upgrade/run.bat")) == Self.batch.data(using: .isoLatin1))
        try? fm.removeItem(at: scratch)
    }
}
