import SwiftUI

struct TimersView: View {
    @StateObject private var engine = SmartTimerEngine.shared
    @State private var showingEditor = false
    @State private var draft = DepartureSchedule(name: "Leave for Work", kind: .fixed)

    var body: some View {
        ZStack {
            AeroBackground(animated: false)
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Auto-Start").font(.aeroTitle).foregroundStyle(.white)
                        Spacer()
                        Button {
                            draft = DepartureSchedule(name: "New Timer", kind: .fixed)
                            showingEditor = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(Aero.bolt)
                        }
                    }

                    if engine.schedules.isEmpty {
                        GlassCard {
                            VStack(spacing: 10) {
                                Image(systemName: "clock.badge.checkmark.fill")
                                    .font(.system(size: 40)).foregroundStyle(Aero.bolt)
                                Text("No timers yet").font(.aeroHeading).foregroundStyle(.white)
                                Text("Add a fixed time or an adaptive timer that learns when you leave home or work and warms up the car before you go.")
                                    .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }

                    ForEach(engine.schedules) { schedule in
                        scheduleCard(schedule)
                    }
                }
                .padding(20)
            }
        }
        .task { await engine.requestPermissionsAndRegister() }
        .sheet(isPresented: $showingEditor) {
            ScheduleEditor(schedule: $draft) {
                engine.add(draft)
                Task { await engine.rescheduleAll() }
            }
        }
    }

    private func scheduleCard(_ schedule: DepartureSchedule) -> some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(schedule.name).font(.aeroHeading).foregroundStyle(.white)
                    Text(subtitle(schedule)).font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                    Text(weekdayString(schedule.weekdays))
                        .font(.aeroCaption).foregroundStyle(Aero.textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { schedule.enabled },
                    set: { var s = schedule; s.enabled = $0; engine.update(s); Task { await engine.rescheduleAll() } }
                ))
                .labelsHidden()
                .tint(Aero.bolt)
            }
        }
        .contextMenu {
            Button(role: .destructive) { engine.remove(schedule) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func subtitle(_ s: DepartureSchedule) -> String {
        switch s.kind {
        case .fixed:
            return String(format: "Starts at %02d:%02d", s.fireHour, s.fireMinute)
        case .adaptive:
            return "Adaptive • \(s.leadMinutes) min before leaving \(s.place.rawValue)"
        }
    }

    private func weekdayString(_ days: Set<Int>) -> String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days.sorted().map { names[$0] }.joined(separator: " ")
    }
}

/// Sheet to create/edit a schedule.
struct ScheduleEditor: View {
    @Binding var schedule: DepartureSchedule
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $schedule.name)
                }
                Section("Type") {
                    Picker("Type", selection: $schedule.kind) {
                        Text("Fixed time").tag(DepartureSchedule.Kind.fixed)
                        Text("Adaptive").tag(DepartureSchedule.Kind.adaptive)
                    }
                    .pickerStyle(.segmented)
                }
                if schedule.kind == .fixed {
                    Section("Start time") {
                        DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    }
                } else {
                    Section("Adaptive") {
                        Picker("Track departures from", selection: $schedule.place) {
                            ForEach(DepartureSchedule.Place.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Stepper("Start \(schedule.leadMinutes) min early",
                                value: $schedule.leadMinutes, in: 2...30)
                    }
                }
                Section("Repeat") {
                    weekdayPicker
                }
            }
            .navigationTitle("Timer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(); dismiss() } }
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents(); c.hour = schedule.fireHour; c.minute = schedule.fireMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                schedule.fireHour = c.hour ?? 7; schedule.fireMinute = c.minute ?? 45
            }
        )
    }

    private var weekdayPicker: some View {
        let names = ["", "S", "M", "T", "W", "T", "F", "S"]
        return HStack {
            ForEach(1...7, id: \.self) { day in
                let on = schedule.weekdays.contains(day)
                Button {
                    if on { schedule.weekdays.remove(day) } else { schedule.weekdays.insert(day) }
                } label: {
                    Text(names[day])
                        .font(.aero(15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(on ? Aero.bolt : Color.gray.opacity(0.2)))
                        .foregroundStyle(on ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
