import SwiftUI
import MapKit

/// Map of nearby chargers. Pulls a wide radius from Open Charge Map and lets you
/// filter to DC fast, Tesla, or ChargePoint. Pins are color-coded by network.
struct ChargerMapView: View {
    @StateObject private var location = LocationProvider.shared
    @State private var stations: [ChargingStation] = []
    @State private var filter: Filter = .dcFast
    @State private var loading = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: ChargingStation?

    private let client = OpenChargeMapClient()

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case dcFast = "DC Fast"
        case tesla = "Tesla"
        case chargePoint = "ChargePoint"
        var id: String { rawValue }
    }

    private var filtered: [ChargingStation] {
        switch filter {
        case .all:        return stations
        case .dcFast:     return stations.filter { $0.speed == .level3 || $0.isTesla }
        case .tesla:      return stations.filter { $0.networkKind == .tesla }
        case .chargePoint:return stations.filter { $0.networkKind == .chargePoint }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera, selection: $selected) {
                UserAnnotation()
                ForEach(filtered) { station in
                    Marker(station.name, systemImage: Self.icon(for: station), coordinate: station.coordinate)
                        .tint(Self.color(for: station))
                        .tag(Optional(station))
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            controls

            if !loading && stations.isEmpty {
                VStack {
                    Spacer()
                    Text(location.current == nil
                         ? "Waiting for your location…"
                         : "No chargers found nearby. Pull the location button to retry.")
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .aeroGlass(cornerRadius: 18)
                        .padding()
                    Spacer()
                }
            }

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
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

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
                    .padding(10)
                    .background(Circle().fill(.ultraThinMaterial))
                }
            }
            Text("\(filtered.count) shown • \(stations.count) within 50 mi")
                .font(.aeroCaption)
                .foregroundStyle(Aero.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .aeroGlass(cornerRadius: 22)
        .padding()
    }

    private func stationCard(_ station: ChargingStation) -> some View {
        GlassCard(glow: Self.color(for: station)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(station.name).font(.aeroHeading).foregroundStyle(.white)
                    Spacer()
                    StatusPill(text: station.networkKind == .other ? station.speed.rawValue : station.networkKind.rawValue,
                               systemImage: Self.icon(for: station),
                               color: Self.color(for: station))
                }
                HStack(spacing: 8) {
                    if station.kw > 0 {
                        Text(String(format: "%.0f kW", station.kw))
                            .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                    }
                    Text(station.speed.rawValue)
                        .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                    if !station.isOperational {
                        Text("• Reported down").font(.aeroCaption).foregroundStyle(Aero.ember)
                    }
                }
                if let origin = location.current {
                    let miles = station.distance(from: origin) / 1609.34
                    Text(String(format: "%.1f mi away", miles))
                        .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                }
                Button {
                    openInMaps(station)
                } label: { Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                    .buttonStyle(GlossyButtonStyle(gradient: Aero.chargeGradient, glow: Aero.aurora))
            }
        }
    }

    // MARK: - Styling

    static func color(for station: ChargingStation) -> Color {
        switch station.networkKind {
        case .tesla:            return Aero.flare
        case .chargePoint:      return Aero.signal
        case .electrifyAmerica: return Aero.iris
        case .evgo:             return Aero.aurora
        case .other:            return station.speed == .level3 ? Aero.aurora : Aero.bolt
        }
    }

    static func icon(for station: ChargingStation) -> String {
        station.isTesla ? "bolt.car.fill" : "bolt.fill"
    }

    private func reload() async {
        guard let coord = location.current else { return }
        loading = true
        defer { loading = false }
        stations = (try? await client.stations(near: coord)) ?? []
    }

    private func openInMaps(_ station: ChargingStation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        item.name = station.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
