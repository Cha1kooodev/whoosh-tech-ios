import SwiftUI
import Foundation

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        ZStack {
            ScooterMap(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    locateButton
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }

            if let scooter = model.selectedScooter {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { model.closeCard() }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ScooterCard(model: model, scooter: scooter)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: 0xC9D3E3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.appBg.opacity(0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.line, lineWidth: 1))
                        .padding(.horizontal, 34)
                        .padding(.bottom, 92)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .background(Color.appBg)
        .animation(.easeOut(duration: 0.22), value: model.selectedID)
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 9) {
            brandRow
            statsRow
            searchField
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.appBg.opacity(0.99),
                    Color.appBg.opacity(0.93),
                    Color.appBg.opacity(0.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var brandRow: some View {
        HStack(spacing: 9) {
            Text("W")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(Color(hex: 0x111111))
                .frame(width: 26, height: 26)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("WHOOSH")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.textPrimary)
            Text("техничка")
                .font(.system(size: 11))
                .foregroundColor(Color.muted)

            Spacer(minLength: 0)
            gpsChip
        }
    }

    private var gpsChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(gpsColor)
                .frame(width: 6, height: 6)
            Text(gpsText)
                .font(.system(size: 9.5, weight: .bold))
        }
        .foregroundColor(gpsColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(gpsColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var gpsColor: Color {
        switch model.gps {
        case .ok:                  return Color(hex: 0x9BE7B4)
        case .denied, .unavailable,
             .timeout:             return Color(hex: 0xFFB4B4)
        case .searching, .idle:    return Color(hex: 0x7B8798)
        }
    }

    private var gpsText: String {
        switch model.gps {
        case .ok:
            let value = Int(model.accuracy.rounded())
            return value > 0 ? "±\(value) м" : "GPS"
        case .searching:   return "поиск…"
        case .denied:      return "нет доступа"
        case .unavailable: return "GPS недоступен"
        case .timeout:     return "таймаут"
        case .idle:        return "GPS"
        }
    }

    private var statsRow: some View {
        HStack(spacing: 6) {
            statCell("всего", model.scooters.count, Color.textPrimary)
            statCell("в доступе", model.count(.available), ScooterStatus.available.color)
            statCell("разряжено", model.count(.low), ScooterStatus.low.color)
            statCell("LOST", model.count(.lost), ScooterStatus.lost.color)
            statCell("украдено", model.count(.stolen), ScooterStatus.stolen.color)
        }
    }

    private func statCell(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 17, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(Color.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.line, lineWidth: 1))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.muted.opacity(0.7))

            TextField("Поиск по номеру — например PSB430", text: $model.query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .font(.system(size: 14))
                .foregroundColor(Color.textPrimary)

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.line, lineWidth: 1))
    }

    private var locateButton: some View {
        Button {
            model.recenterOnUser()
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(model.followUser ? Color.accent : Color.textPrimary)
                .frame(width: 46, height: 46)
                .background(Color.panel.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.line, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.5), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}
