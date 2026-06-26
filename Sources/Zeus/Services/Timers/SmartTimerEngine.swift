import Foundation
import UserNotifications
import BackgroundTasks
import CoreLocation

/// A recurring scheduled remote-start. Two flavors:
/// - `.fixed`: fire at a set clock time on chosen weekdays (e.g. 7:45am for work).
/// - `.adaptive`: learn when you typically leave a place (home/work) and pre-start
///   the car a lead time before that learned departure.
struct DepartureSchedule: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case fixed, adaptive }
    enum Place: String, Codable, CaseIterable { case home = "Home", work = "Work" }

    var id = UUID()
    var name: String
    var kind: Kind
    var enabled: Bool = true
    /// For `.fixed`: the time of day to start. For `.adaptive`: ignored.
    var fireHour: Int = 7
    var fireMinute: Int = 45
    /// 1 = Sunday ... 7 = Saturday (Calendar weekday).
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    /// For `.adaptive`: which place's departure pattern to track.
    var place: Place = .home
    /// Minutes before the (scheduled/learned) departure to start the car.
    var leadMinutes: Int = 10
}

/// Owns the schedules, persists them, registers notifications + background
/// refresh, and learns adaptive departure times from significant-location
/// visits.
@MainActor
final class SmartTimerEngine: ObservableObject {
    static let shared = SmartTimerEngine()
    static let bgTaskID = "com.zeus.bolt.autostart"

    @Published var schedules: [DepartureSchedule] = []

    private let storeKey = "zeus.schedules"
    /// Rolling learned departure minute-of-day per place (exponential average).
    private var learnedDeparture: [DepartureSchedule.Place: Int] = [:]

    private init() { load() }

    // MARK: - CRUD

    func add(_ schedule: DepartureSchedule) { schedules.append(schedule); persist() }
    func update(_ schedule: DepartureSchedule) {
        if let i = schedules.firstIndex(where: { $0.id == schedule.id }) { schedules[i] = schedule }
        persist()
    }
    func remove(_ schedule: DepartureSchedule) {
        schedules.removeAll { $0.id == schedule.id }; persist()
    }

    // MARK: - Scheduling

    func requestPermissionsAndRegister() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        await rescheduleAll()
    }

    /// Register OS background task. Call once from app launch.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { await SmartTimerEngine.shared.handleBackgroundFire(task) }
        }
    }

    func rescheduleAll() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for schedule in schedules where schedule.enabled {
            let fire = nextFireTime(for: schedule)
            scheduleLocalNotification(for: schedule, at: fire)
            scheduleBackgroundStart(at: fire)
        }
    }

    /// When the background task fires, start the car for any schedule due now.
    private func handleBackgroundFire(_ task: BGAppRefreshTask) async {
        let now = minuteOfDay(Date())
        let due = schedules.contains { $0.enabled && abs(minuteOfDay(nextFireTime(for: $0)) - now) <= 5 }
        if due {
            try? await RemoteCommandService.shared.perform(.start)
        }
        await rescheduleAll()
        task.setTaskCompleted(success: true)
    }

    // MARK: - Adaptive learning

    /// Feed a detected departure (called by the visit/geofence monitor) so the
    /// adaptive schedule converges on your real routine.
    func recordDeparture(from place: DepartureSchedule.Place, at date: Date) {
        let minute = minuteOfDay(date)
        let prior = learnedDeparture[place] ?? minute
        // Exponential moving average — recent days weighted ~30%.
        learnedDeparture[place] = Int(Double(prior) * 0.7 + Double(minute) * 0.3)
        persist()
        Task { await rescheduleAll() }
    }

    // MARK: - Time math

    private func nextFireTime(for schedule: DepartureSchedule) -> Date {
        let cal = Calendar.current
        let baseMinute: Int
        switch schedule.kind {
        case .fixed:
            baseMinute = schedule.fireHour * 60 + schedule.fireMinute
        case .adaptive:
            let learned = learnedDeparture[schedule.place] ?? (8 * 60)
            baseMinute = learned - schedule.leadMinutes
        }
        // Find the next matching weekday at baseMinute.
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let weekday = cal.component(.weekday, from: day)
            guard schedule.weekdays.contains(weekday) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = baseMinute / 60
            comps.minute = baseMinute % 60
            if let fire = cal.date(from: comps), fire > Date() { return fire }
        }
        return Date().addingTimeInterval(86_400)
    }

    private func scheduleLocalNotification(for schedule: DepartureSchedule, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Zeus • \(schedule.name)"
        content.body = "Pre-starting your Bolt so it's ready when you leave. ⚡️"
        content.sound = .default
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: schedule.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func scheduleBackgroundStart(at date: Date) {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskID)
        request.earliestBeginDate = date.addingTimeInterval(-60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(schedules) {
            AppGroup.defaults.set(data, forKey: storeKey)
        }
    }
    private func load() {
        guard let data = AppGroup.defaults.data(forKey: storeKey),
              let saved = try? JSONDecoder().decode([DepartureSchedule].self, from: data) else { return }
        schedules = saved
    }
}
