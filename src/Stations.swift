import Foundation

struct Station {
    let name: String
    let logo: String
    let site: URL
    let stream: URL
    let songURL: URL
    let song: (Data) -> String?
    // nil: the show comes from the song's own response.
    let showURL: URL?
    let show: (Data) -> String?
}

func nonEmpty(_ values: [Any?]) -> [String] {
    values.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

private func json(_ data: Data) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func text(matching pattern: String, in html: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
          let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
          let range = Range(match.range(at: 1), in: html) else { return nil }
    var text = html[range].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#039;": "'", "&nbsp;": " "] {
        text = text.replacingOccurrences(of: entity, with: char)
    }
    return nonEmpty([text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)]).first
}

let stations = [
    Station(
        name: "Radio 357",
        logo: "logo-357",
        site: URL(string: "https://radio357.pl")!,
        stream: URL(string: "https://stream.radio357.pl")!,
        songURL: URL(string: "https://stream.radio357.pl/now/playing.json")!,
        // Between songs "s" carries the station's slogan instead of a song.
        song: { data in
            guard let song = nonEmpty([json(data)?["s"]]).first, !song.hasPrefix("Radio 357") else { return nil }
            return song.replacingOccurrences(of: " - ", with: " – ")
        },
        showURL: nil,
        show: { data in
            let show = json(data)?["p"] as? [String: Any]
            let parts = nonEmpty([show?["n"], show?["a"]])
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    ),
    Station(
        name: "Nowy Świat",
        logo: "logo-ns",
        site: URL(string: "https://nowyswiat.online")!,
        stream: URL(string: "https://stream.nowyswiat.online/mp3")!,
        songURL: URL(string: "https://nowyswiat.online/api/oZeta/stat")!,
        // The API names the fields the other way round: "title" holds the artist, "artist" the song; between
        // songs "title" is the station's name.
        song: { data in
            let fields = json(data)?["data"] as? [String: Any]
            let parts = nonEmpty([fields?["title"], fields?["artist"]])
            guard parts.count == 2, parts[0] != "Radio Nowy Świat" else { return nil }
            return parts.joined(separator: " – ")
        },
        showURL: URL(string: "https://nowyswiat.online/")!,
        show: { data in
            guard let html = String(data: data, encoding: .utf8),
                  let slide = html.range(of: "rns-slide-schedule-now").map({ String(html[$0.upperBound...].prefix(4000)) }) else { return nil }
            let parts = nonEmpty([
                text(matching: #"rns-slider-text-large"><span>(.*?)</span>"#, in: slide),
                text(matching: #"Zaprasza\S*(.*?)</p>"#, in: slide),
            ])
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    ),
]
