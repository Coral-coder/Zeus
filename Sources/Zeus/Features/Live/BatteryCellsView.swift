import SwiftUI

/// The HV battery, cell by cell: all 96 cells in a grid, each shaded on a
/// red → green scale (red = low/dead, green = full), plus the pack as a whole.
/// Data comes from the OBD-II per-cell sweep (OBDManager.requestCellSweep).
struct BatteryCellsView: View {
    @ObservedObject private var obd = OBDManager.shared

    /// Absolute voltage scale for the colour ramp: red at `lo`, green at `hi`.
    /// Bolt cells run ~3.0 V (empty) to ~4.15 V (full).
    private let lo = 3.2
    private let hi = 4.15

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 6)]

    private var cells: [Double] { obd.cellVoltages }
    private var known: [Double] { cells.filter { $0 > 0 } }
    private var minV: Double? { known.min() }
    private var maxV: Double? { known.max() }
    private var avg: Double? { known.isEmpty ? nil : known.reduce(0, +) / Double(known.count) }

    var body: some View {
        ZStack {
            AeroBackground(animated: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if obd.isConnected {
                        packGauge
                        statsRow
                        legend
                        grid
                    } else {
                        notConnected
                    }
                    Spacer(minLength: 8)
                }
                .padding(20)
            }
        }
        .navigationTitle("Battery Cells")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { obd.requestCellSweep() } label: {
                    if obd.cellSweepActive {
                        ProgressView().tint(Aero.bolt)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(obd.cellSweepActive || !obd.isConnected)
            }
        }
        .onAppear { obd.requestCellSweep() }
    }

    // MARK: - Pack gauge (whole battery, red → green)

    private var packFraction: Double {
        if let soc = obd.readings["2243AF"]?.value { return max(0, min(1, soc / 100)) }
        if let a = avg { return clampFraction(a) }
        return 0
    }

    private var packGauge: some View {
        GlassCard(glow: Aero.aurora) {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((packFraction * 100).rounded()))")
                        .font(.aero(44, weight: .heavy))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("%").font(.aero(20, weight: .bold)).foregroundStyle(Aero.textSecondary)
                    Spacer()
                    if let a = avg {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("PACK AVG").font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Aero.textTertiary)
                            Text(String(format: "%.3f V", a))
                                .font(.aero(15, weight: .bold)).foregroundStyle(.white).monospacedDigit()
                        }
                    }
                }

                // Red → green scale bar with a marker at the current level.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(height: 16)
                        // Position marker.
                        Capsule()
                            .fill(.white)
                            .frame(width: 3, height: 24)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .offset(x: max(0, min(geo.size.width - 3, geo.size.width * packFraction)))
                            .offset(y: -4)
                    }
                }
                .frame(height: 24)
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("Min", minV.map { String(format: "%.3f V", $0) } ?? "—", Aero.flare)
            stat("Max", maxV.map { String(format: "%.3f V", $0) } ?? "—", Aero.aurora)
            stat("Spread", (minV != nil && maxV != nil)
                 ? "\(Int(((maxV! - minV!) * 1000).rounded())) mV" : "—", Aero.bolt)
            stat("Cells", "\(obd.cellsReadCount)/96", Aero.iris)
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Aero.textTertiary)
            Text(value).font(.aero(14, weight: .bold)).foregroundStyle(.white)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.4)))
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("LOW").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Aero.textTertiary)
            Capsule()
                .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 8)
            Text("FULL").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Aero.textTertiary)
        }
    }

    // MARK: - Cell grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(cells.indices, id: \.self) { i in
                cellTile(index: i, volts: cells[i])
            }
        }
    }

    private func cellTile(index: Int, volts: Double) -> some View {
        let isExtreme = (volts > 0) && (volts == minV || volts == maxV)
        return VStack(spacing: 1) {
            Text("\(index + 1)")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.55))
            Text(volts > 0 ? String(format: "%.2f", volts) : "–")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.black.opacity(0.8))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color(for: volts)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isExtreme ? .white : .white.opacity(0.15),
                              lineWidth: isExtreme ? 2 : 1)
        )
    }

    // MARK: - Colour ramp

    private func clampFraction(_ v: Double) -> Double { max(0, min(1, (v - lo) / (hi - lo))) }

    /// Red (low) → green (full). Unread cells are dim grey.
    private func color(for v: Double) -> Color {
        guard v > 0 else { return Color.white.opacity(0.08) }
        let f = clampFraction(v)
        // Hue 0 (red) → 0.33 (green).
        return Color(hue: 0.33 * f, saturation: 0.85, brightness: 0.95)
    }

    private var notConnected: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: "bolt.car.circle")
                    .font(.system(size: 44)).foregroundStyle(Aero.bolt)
                Text("Connect a Bluetooth OBD-II adapter on the Live tab to read all 96 cell voltages.")
                    .font(.aeroBody).foregroundStyle(Aero.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    NavigationStack { BatteryCellsView() }
}
