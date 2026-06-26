import SwiftUI
import MapKit

/// Map of nearby chargers with a Level 2 / DC-fast filter and a "nearest"
/// callout. Uses the new MapKit SwiftUI API (iOS 17+).
struct ChargerMapView: View {
    @StateObject private var location = LocationProvider.shared
    @State private var stations: [ChargingStation] = []
    @State private var fastOnly = false
    @State private var loading = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: ChargingStation?

    private let client = OpenChargeMapClient()

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera, selection: $selected) {
                UserAnnotation()
                ForEach(stations) { station in
                    Marker(station.name, systemImage: "bolt.fill", coordinate: station.coordinate)
                        .tint(station.speed == .level3 ? Aero.aurora : Aero.bolt)
                        .tag(Optional(station))
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            controls

            if let selected {
                VStack {
                    Spacer()
                    stationCard(selected)
                        .padding()
                }
            }
        }
        .onAppear {
            location.requestWhenInUse()
            location.start()
        }
        .onChange(of: location.current?.latitude) { _, _ in
            Task { await reload() }
        }
        .task { await reload() }
    }

    private var controls: some View {
        HStack {
            Picker("", selection: $fastOnly) {
                Text("All").tag(false)
                Text("DC Fast").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: fastOnly) { _, _ in Task { await reload() } }

            Spacer()

            Button {
                Task { await reload() }
            } label: {
                Group {
                    if loading {
                        ProgressView().tint(Aero.bolt)
                    } else {
                        Image(systemName: "location.fill").foregroundStyle(Aero.bolt)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(12)
                .background(Circle().fill(.ultraThinMaterial))
            }
        }
        .padding(12)
        .aeroGlass(cornerRadius: 22)
        .padding()
    }

    private func stationCard(_ station: ChargingStation) -> some View {
        GlassCard(glow: station.speed == .level3 ? Aero.aurora : Aero.bolt) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(station.name).font(.aeroHeading).foregroundStyle(.white)
                    Spacer()
                    StatusPill(text: station.speed.rawValue,
                               systemImage: "bolt.fill",
                               color: station.speed == .level3 ? Aero.aurora : Aero.bolt)
                }
                if let net = station.network {
                    Text(net).font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                }
                if let origin = location.current {
                    let miles = station.distance(from: origin) / 1609.34
                    Text(String(format: "%.1f mi away • %@", miles, station.speed.maxKW))
                        .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                }
                Button {
                    openInMaps(station)
                } label: { Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                    .buttonStyle(GlossyButtonStyle(gradient: Aero.chargeGradient, glow: Aero.aurora))
            }
        }
    }

    private func reload() async {
        guard let coord = location.current else { return }
        loading = true
        defer { loading = false }
        stations = (try? await client.stations(near: coord, fastOnly: fastOnly)) ?? []
    }

    private func openInMaps(_ station: ChargingStation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        item.name = station.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
