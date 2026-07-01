import Foundation

/// One animation frame of weather radar: a timestamp and the tile path that
/// builds into a slippy-map tile URL.
struct RadarFrame: Identifiable, Equatable {
    let time: Int
    let path: String
    var id: Int { time }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(time)) }
}

/// Fetches the current global weather-radar frame index from RainViewer's free,
/// key-less public API (https://www.rainviewer.com/api.html). Frames are tile
/// layers we overlay on a map and cycle to animate precipitation.
struct RainViewerClient {
    private let indexURL = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!

    /// Returns the tile host and the ordered frames (past → nowcast/forecast).
    func frames() async throws -> (host: String, frames: [RadarFrame]) {
        let (data, resp) = try await URLSession.shared.data(from: indexURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = root["host"] as? String,
              let radar = root["radar"] as? [String: Any]
        else { return ("https://tilecache.rainviewer.com", []) }

        func parse(_ key: String) -> [RadarFrame] {
            (radar[key] as? [[String: Any]] ?? []).compactMap { f in
                guard let t = f["time"] as? Int, let p = f["path"] as? String else { return nil }
                return RadarFrame(time: t, path: p)
            }
        }
        let frames = parse("past") + parse("nowcast")
        return (host, frames)
    }

    /// Build an MKTileOverlay-style URL template for one frame.
    /// `color`: RainViewer color scheme (4 = The Weather Channel). `smooth`/`snow` on.
    static func tileTemplate(host: String, frame: RadarFrame, color: Int = 4) -> String {
        "\(host)\(frame.path)/256/{z}/{x}/{y}/\(color)/1_1.png"
    }
}
