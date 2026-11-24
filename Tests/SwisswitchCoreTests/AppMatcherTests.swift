import Foundation
import Testing
@testable import SwisswitchCore

private func app(_ name: String, _ pid: pid_t, aliases: [String] = [], front: Bool = false) -> AppCandidate {
    AppCandidate(name: name, aliases: aliases, pid: pid, isFrontmost: front)
}

@Test func singleMatch() {
    let apps = [app("Safari", 1), app("Terminal", 2)]
    #expect(pickApp(for: "s", among: apps)?.name == "Safari")
    #expect(pickApp(for: "T", among: apps)?.name == "Terminal")
}

@Test func noMatch() {
    #expect(pickApp(for: "z", among: [app("Safari", 1)]) == nil)
    #expect(pickApp(for: "a", among: []) == nil)
}

@Test func foldsCaseAndDiacritics() {
    #expect(pickApp(for: "e", among: [app("Écran", 1)])?.name == "Écran")
    #expect(pickApp(for: "f", among: [app("finder", 1)])?.name == "finder")
}

@Test func firstByNameWhenFrontmostDoesNotMatch() {
    let apps = [app("Slack", 1), app("Safari", 2), app("Notes", 3, front: true)]
    #expect(pickApp(for: "s", among: apps)?.name == "Safari")
}

@Test func cyclesFromFrontmostAndWraps() {
    let apps = [app("Slack", 1), app("Safari", 2, front: true), app("Spotify", 3)]
    #expect(pickApp(for: "s", among: apps)?.name == "Slack")
    let wrapped = [app("Slack", 1), app("Safari", 2), app("Spotify", 3, front: true)]
    #expect(pickApp(for: "s", among: wrapped)?.name == "Safari")
}

@Test func singleFrontmostMatchStaysPut() {
    #expect(pickApp(for: "s", among: [app("Safari", 1, front: true)])?.name == "Safari")
}

@Test func matchesNonLocalizedAlias() {
    let apps = [app("访达", 1, aliases: ["Finder"]), app("音乐", 2, aliases: ["Music"])]
    #expect(pickApp(for: "f", among: apps)?.pid == 1)
    #expect(pickApp(for: "m", among: apps)?.pid == 2)
}
