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

@Test func latinNameIgnoresAliases() {
    let apps = [app("Google Chrome", 1, aliases: ["Google Chrome", "Chrome"])]
    #expect(pickApp(for: "g", among: apps)?.pid == 1)
    #expect(pickApp(for: "c", among: apps) == nil)
}

@Test func onlyFirstAliasCounts() {
    let apps = [app("飞书", 1, aliases: ["Feishu", "Lark"])]
    #expect(pickApp(for: "f", among: apps)?.pid == 1)
    #expect(pickApp(for: "l", among: apps) == nil)
}

private func scored(_ name: String, _ pid: pid_t, _ score: Double, front: Bool = false) -> AppCandidate {
    AppCandidate(name: name, pid: pid, isFrontmost: front, score: score)
}

@Test func higherScoreBeatsAlphabetical() {
    let apps = [scored("Safari", 1, 1), scored("Surge", 2, 5)]
    #expect(pickApp(for: "s", among: apps)?.name == "Surge")
}

@Test func cyclesInScoreOrder() {
    let apps = [scored("Safari", 1, 1), scored("Surge", 2, 5, front: true), scored("Slack", 3, 3)]
    #expect(pickApp(for: "s", among: apps)?.name == "Slack")
    let next = [scored("Safari", 1, 1), scored("Surge", 2, 5), scored("Slack", 3, 3, front: true)]
    #expect(pickApp(for: "s", among: next)?.name == "Safari")
    let wrap = [scored("Safari", 1, 1, front: true), scored("Surge", 2, 5), scored("Slack", 3, 3)]
    #expect(pickApp(for: "s", among: wrap)?.name == "Surge")
}

@Test func groupsByLetterInPressOrder() {
    let apps = [scored("Safari", 1, 0), scored("Surge", 2, 2), scored("Notes", 3, 0),
                AppCandidate(name: "访达", aliases: ["Finder"], pid: 4, isFrontmost: false)]
    let groups = groupedApps(apps)
    #expect(groups.map(\.letter) == ["f", "n", "s"])
    #expect(groups.last?.apps.map(\.name) == ["Surge", "Safari"])
    #expect(groups.first?.apps.first?.pid == 4)
}

@Test func idDefaultsToName() {
    #expect(AppCandidate(name: "Safari", pid: 1, isFrontmost: false).id == "Safari")
    #expect(AppCandidate(name: "Safari", id: "com.apple.Safari", pid: 1, isFrontmost: false).id == "com.apple.Safari")
}
