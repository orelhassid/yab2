import Foundation

extension ChatItem {
    /// What the Artifact tool's answer says it published, from its words:
    /// "Published <path> at https://claude.ai/artifact/… (Version 1 …) Icon: "x"".
    static func published(_ words: String) -> [String: String]? {
        guard let found = words.firstMatch(of: #/(?:Published|Updated|Republished) (.+?) at (https:\/\/claude\.ai\/(?:code\/)?artifact\/[A-Za-z0-9\-]+)/#) else { return nil }
        var out = ["artifact": String(found.output.2), "artifactPath": String(found.output.1)]
        if let icon = words.firstMatch(of: #/Icon: "([^"]+)"/#) { out["icon"] = String(icon.output.1) }
        if let version = words.firstMatch(of: #/\(Version ([0-9]+)/#) { out["artifactSeq"] = String(version.output.1) }
        return out
    }

    /// The same from the tool's structured answer (`toolUseResult` in a
    /// transcript, `tool_use_result` in the stream): its title too, its id,
    /// its version and the files beside the page, by which Yab keeps a copy
    /// of it (ArtifactPages).
    static func published(result: Any?) -> [String: String]? {
        guard let result = result as? [String: Any], let url = result["url"] as? String,
              url.contains("claude.ai/") && url.contains("artifact/") else { return nil }
        var out = ["artifact": url]
        if let title = result["title"] as? String, !title.isEmpty { out["title"] = title }
        if let icon = result["icon"] as? String, !icon.isEmpty { out["icon"] = icon }
        if let path = result["path"] as? String, !path.isEmpty { out["artifactPath"] = path }
        if let id = result["artifact_id"] as? String, !id.isEmpty { out["artifactID"] = id }
        // Its version: 2 once it is published again (the card's "Version 2").
        if let seq = (result["seq"] as? NSNumber)?.intValue, seq > 0 { out["artifactSeq"] = String(seq) }
        let files = (result["files_written"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }.filter { !$0.isEmpty }
        if !files.isEmpty { out["artifactFiles"] = files.joined(separator: "\n") }
        return out
    }
}

extension Array where Element == ChatItem {
    /// A tool's structured answer kept on its step, for its card.
    mutating func kept(_ result: Any?, for id: String) {
        guard let more = ChatItem.published(result: result), let index = lastIndex(where: { $0.id == id }) else { return }
        self[index].extra = (self[index].extra ?? [:]).merging(more) { $1 }
    }
}
