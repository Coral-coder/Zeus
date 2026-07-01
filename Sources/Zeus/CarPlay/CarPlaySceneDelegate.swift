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

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let tabs = CPTabBarTemplate(templates: [chargerTab(), dashboardTab()])
        interfaceController.setRootTemplate(tabs, animated: true, completion: nil)
        Task { await refreshChargers() }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
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
        let snap = SnapshotStore.load() ?? .placeholder()
        var rows: [CPListItem] = [
            CPListItem(text: "Battery", detailText: "\(Int(snap.batteryLevel * 100))%"),
            CPListItem(text: "Range", detailText: snap.rangeMiles.map { "\($0) mi" } ?? "—"),
            CPListItem(text: "Charging", detailText: snap.isCharging ? "Yes" : "No"),
            CPListItem(text: "Doors", detailText: snap.locked ? "Locked" : "Unlocked")
        ]
        // Everything else OnStar reported.
        let shown: Set<String> = ["Battery", "Range"]
        for stat in snap.stats ?? [] where !shown.contains(stat.label) {
            rows.append(CPListItem(text: stat.label, detailText: stat.value))
        }
        var sections = [CPListSection(items: rows, header: "OnStar", sectionIndexTitle: nil)]

        // Live OBD parameters, when the reader is connected.
        let live = OBDManager.shared.latestReadable
        if !live.isEmpty {
            let liveRows = live.map { CPListItem(text: $0.label, detailText: $0.formatted) }
            sections.append(CPListSection(items: liveRows, header: "Live (OBD)", sectionIndexTitle: nil))
        }
        dashboardTemplate.updateSections(sections)
    }
}
