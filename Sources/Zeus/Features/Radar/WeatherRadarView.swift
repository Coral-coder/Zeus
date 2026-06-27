import SwiftUI
import MapKit
import CoreLocation

/// Drives the radar animation: fetches frames, advances the current frame on a
/// timer, and exposes the current tile URL template for the map to render.
@MainActor
final class WeatherRadarModel: ObservableObject {
    @Published private(set) var host = "https://tilecache.rainviewer.com"
    @Published private(set) var frames: [RadarFrame] = []
    @Published private(set) var index = 0
    @Published var playing = false
    @Published private(set) var loading = false

    private let client = RainViewerClient()
    private var timer: Timer?

    var current: RadarFrame? { frames.indices.contains(index) ? frames[index] : nil }
    var currentTemplate: String? {
        current.map { RainViewerClient.tileTemplate(host: host, frame: $0) }
    }

    func load() async {
        loading = true
        defer { loading = false }
        if let result = try? await client.frames(), !result.frames.isEmpty {
            host = result.host
            frames = result.frames
            // Show the most recent frame, static, so current radar renders fully
            // before any animation churns through tiles.
            index = frames.count - 1
            if playing { startTimer() }
        }
    }

    func togglePlay() {
        playing.toggle()
        playing ? startTimer() : timer?.invalidate()
    }

    func scrub(to i: Int) {
        index = min(max(0, i), max(0, frames.count - 1))
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.frames.isEmpty else { return }
                self.index = (self.index + 1) % self.frames.count
            }
        }
    }

    deinit { timer?.invalidate() }
}

/// Animated weather-radar tab: precipitation tiles overlaid on a dark map,
/// sweeping through recent + nowcast frames.
struct WeatherRadarView: View {
    @StateObject private var model = WeatherRadarModel()
    @StateObject private var location = LocationProvider.shared

    private var statusText: String {
        if model.loading { return "Loading…" }
        if model.frames.isEmpty { return "No radar data — tap to retry" }
        if let f = model.current {
            return f.date.formatted(date: .omitted, time: .shortened) + " · live"
        }
        return "\(model.frames.count) frames"
    }

    var body: some View {
        ZStack(alignment: .top) {
            RadarMap(urlTemplate: model.currentTemplate,
                     center: location.current)
                .ignoresSafeArea()

            topBar
            VStack {
                Spacer()
                Text("Radar shows precipitation only — clear skies look empty.")
                    .font(.aeroCaption)
                    .foregroundStyle(Aero.textTertiary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                timeline
            }
        }
        .onAppear {
            location.requestWhenInUse()
            location.start()
        }
        .task { await model.load() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.rain.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Aero.bolt)
            VStack(alignment: .leading, spacing: 1) {
                Text("WEATHER RADAR")
                    .font(.aero(16, weight: .heavy))
                    .foregroundStyle(.white)
                Text(statusText)
                    .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
            }
            Spacer()
            if model.loading {
                ProgressView().tint(Aero.bolt)
            } else if model.frames.isEmpty {
                Button { Task { await model.load() } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(Aero.bolt)
                }
            }
        }
        .padding(14)
        .aeroGlass(cornerRadius: 22)
        .padding()
    }

    private var timeline: some View {
        HStack(spacing: 14) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30)
            }
            if model.frames.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(model.index) },
                        set: { model.scrub(to: Int($0.rounded())) }
                    ),
                    in: 0...Double(model.frames.count - 1),
                    step: 1
                )
                .tint(Aero.bolt)
            }
        }
        .padding(14)
        .aeroGlass(cornerRadius: 22)
        .padding()
    }
}

/// MKMapView wrapper that renders one radar tile layer and swaps it when the
/// frame's URL template changes (the animation).
struct RadarMap: UIViewRepresentable {
    let urlTemplate: String?
    let center: CLLocationCoordinate2D?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.overrideUserInterfaceStyle = .dark
        // Center on the user if known, else a wide continental-US view so the
        // map (and any precipitation) is visible immediately.
        let start = center ?? CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35)
        let span = center == nil ? MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
                                 : MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)
        map.setRegion(MKCoordinateRegion(center: start, span: span), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Recenter once we get a location, if the user hasn't moved the map.
        if let center, !context.coordinator.didCenter {
            map.setRegion(MKCoordinateRegion(center: center,
                                             span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)),
                          animated: false)
            context.coordinator.didCenter = true
        }

        guard context.coordinator.template != urlTemplate else { return }
        context.coordinator.template = urlTemplate

        guard let urlTemplate else {
            if let old = context.coordinator.overlay { map.removeOverlay(old) }
            context.coordinator.overlay = nil
            return
        }
        // Add the new layer first, then remove the previous one, so there's no
        // blank gap while the new frame's tiles download.
        let overlay = MKTileOverlay(urlTemplate: urlTemplate)
        overlay.canReplaceMapContent = false
        overlay.maximumZ = 12
        map.addOverlay(overlay, level: .aboveLabels)
        if let old = context.coordinator.overlay {
            // Give the new tiles a moment to load before pulling the old layer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                map.removeOverlay(old)
            }
        }
        context.coordinator.overlay = overlay
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var overlay: MKTileOverlay?
        var template: String?
        var didCenter = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tile)
                r.alpha = 0.85
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
