import CarPlay
import CoreLocation
import MapKit
import UIKit

/// CarPlay scene: a tabbed dashboard showing (1) nearby chargers split into
/// Level 2 / DC fast lists, and (2) live vehicle parameters (from OnStar
/// diagnostics and, when connected, the OBD-II reader).
///
/// CarPlay requires a CarPlay app entitlement from Apple (request at
/// developer.apple.com → CarPlay). Until granted this builds but won't appear
/// on the head unit. The Info.plist must declare the
/// `CPTemplateApplicationSceneSessionRoleApplication` scene → this delegate.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    var interfaceController: CPInterfaceController?
    private let ocm = OpenChargeMapClient()
    /// Keeps the live-voltage dashboard ticking on the head unit.
    private var dashboardTimer: Timer?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let tabs = CPTabBarTemplate(templates: [chargerTab(), dashboardTab()])
        interfaceController.setRootTemplate(tabs, animated: true, completion: nil)
        Task { await refreshChargers() }
        startDashboardRefresh()
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        dashboardTimer?.invalidate()
        dashboardTimer = nil
    }

    /// Re-render the dashboard every couple of seconds so live OBD voltages
    /// update on the car's screen while connected.
    private func startDashboardRefresh() {
        dashboardTimer?.invalidate()
        dashboardTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDashboard()
        }
    }

    // MARK: - Chargers tab

    private var chargerListTemplate = CPListTemplate(title: "Chargers", sections: [])

    private func chargerTab() -> CPListTemplate {
        chargerListTemplate.tabTitle = "Chargers"
        chargerListTemplate.tabImage = UIImage(systemName: "bolt.fill")
        return chargerListTemplate
    }

    private func refreshChargers() async {
        guard let coord = LocationProvider.shared.current else { return }
        let stations = (try? await ocm.stations(near: coord, radiusMiles: 30)) ?? []
        let fast = stations.filter { $0.speed == .level3 }
        let level2 = stations.filter { $0.speed == .level2 }

        func items(_ list: [ChargingStation]) -> [CPListItem] {
            list.prefix(20).map { station in
                let miles = String(format: "%.1f mi", station.distance(from: coord) / 1609.34)
                let item = CPListItem(text: station.name, detailText: "\(miles) • \(station.network ?? "")")
                item.handler = { _, completion in
                    let placemark = MKPlacemark(coordinate: station.coordinate)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = station.name
                    mapItem.openInMaps(launchOptions:
                        [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    completion()
                }
                return item
            }
        }

        await MainActor.run {
            chargerListTemplate.updateSections([
                CPListSection(items: items(fast), header: "⚡️ DC Fast", sectionIndexTitle: nil),
                CPListSection(items: items(level2), header: "Level 2", sectionIndexTitle: nil)
            ])
        }
    }

    // MARK: - Dashboard tab

    private let dashboardTemplate = CPListTemplate(title: "Bolt", sections: [])

    private func dashboardTab() -> CPListTemplate {
        dashboardTemplate.tabTitle = "Bolt"
        dashboardTemplate.tabImage = UIImage(systemName: "bolt.car.fill")
        refreshDashboard()
        return dashboardTemplate
    }

    private func refreshDashboard() {
        let obd = OBDManager.shared
        var sections: [CPListSection] = []

        // Live battery voltages first — the headline on the head unit. Ordered
        // so HV pack + 12V + cell spread lead.
        if obd.isConnected {
            let order = ["0142", "ATRV", "22433C", "22433B", "2243AF", "2240D4", "22434F", "010D"]
            let ordered = Set(order)
            var rows: [CPListItem] = []
            for cmd in order {
                if let r = obd.readings[cmd] {
                    rows.append(CPListItem(text: r.label, detailText: r.formatted))
                }
            }
            for r in obd.latestReadable where !ordered.contains(r.command) {
                rows.append(CPListItem(text: r.label, detailText: r.formatted))
            }
            // Cell spread (weakest-to-strongest), the key pack-health number.
            // CarPlay can't draw the full 96-cell grid — that lives in the app;
            // here we surface the headline cell metrics.
            if let mx = obd.readings["22433C"]?.value, let mn = obd.readings["22433B"]?.value {
                rows.append(CPListItem(text: "Cell Spread", detailText: "\(Int(((mx - mn) * 1000).rounded())) mV"))
            }
            if !rows.isEmpty {
                sections.append(CPListSection(items: rows, header: "⚡️ Live Battery (OBD)", sectionIndexTitle: nil))
            }
        }

        // OnStar snapshot summary (always available from the shared cache).
        let snap = SnapshotStore.load() ?? .placeholder()
        var rows: [CPListItem] = [
            CPListItem(text: "Battery", detailText: "\(Int(snap.batteryLevel * 100))%"),
            CPListItem(text: "Range", detailText: snap.rangeMiles.map { "\($0) mi" } ?? "—"),
            CPListItem(text: "Charging", detailText: snap.isCharging ? "Yes" : "No"),
            CPListItem(text: "Doors", detailText: snap.locked ? "Locked" : "Unlocked")
        ]
        if let v = snap.voltage12V {
            rows.append(CPListItem(text: "12V Battery", detailText: String(format: "%.1f V", v)))
        }
        sections.append(CPListSection(items: rows, header: "OnStar", sectionIndexTitle: nil))

        dashboardTemplate.updateSections(sections)
    }
}
