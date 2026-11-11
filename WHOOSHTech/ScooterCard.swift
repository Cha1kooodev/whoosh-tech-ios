import SwiftUI
import Foundation
import UIKit

struct RoundedCorner: Shape {
    var radius: CGFloat = 22
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct ScooterCard: View {
    @ObservedObject var model: AppModel
    let scooter: Scooter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(hex: 0x2B3444))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 12)

            HStack(spacing: 10) {
                Text(scooter.code)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(Color.textPrimary)
                Spacer(minLength: 6)
                statusChip
            }

            Text(scooter.model)
                .font(.system(size: 12.5))
                .foregroundColor(Color.muted)
                .padding(.top, 4)

            VStack(spacing: 8) {
                batteryRow
                geoRow
                distanceRow
            }
            .padding(.top, 14)

            warningView

            Text("СТАТУС ТС")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.7)
                .foregroundColor(Color(hex: 0x6D7989))
                .padding(.top, 16)
                .padding(.bottom, 8)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(ScooterStatus.allCases, id: \.self) { status in
                    statusButton(status)
                }
            }

            Button {
                model.closeCard()
            } label: {
                Text("Закрыть")
                    .font(.system(size: 13))
                    .foregroundColor(Color.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 34)
        .background(Color.panel)
        .clipShape(RoundedCorner(radius: 22, corners: [.topLeft, .topRight]))
        .shadow(color: Color.black.opacity(0.6), radius: 24, y: -8)
    }

    // MARK: - Части

    private var statusChip: some View {
        Text(scooter.status.title)
            .font(.system(size: 10.5, weight: .heavy))
            .foregroundColor(scooter.status.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(scooter.status.color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(scooter.status.color.opacity(0.4), lineWidth: 1))
    }

    private var batteryRow: some View {
        infoRow("Заряд") {
            HStack(spacing: 10) {
                Text("\(scooter.battery)%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Color.textPrimary)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x232B3A))
                    GeometryReader { geo in
                        Capsule()
                            .fill(batteryColor)
                            .frame(width: max(4, geo.size.width * CGFloat(scooter.battery) / 100))
                    }
                }
                .frame(width: 92, height: 7)
            }
        }
    }

    private var batteryColor: Color {
        if scooter.battery > 60 { return Color(hex: 0x22C55E) }
        if scooter.battery > 20 { return Color(hex: 0xF59E0B) }
        return Color(hex: 0xEF4444)
    }

    private var geoRow: some View {
        let coordinate = scooter.coordinate
        let stolen = scooter.status == .stolen
        return infoRow(stolen ? "Последнее гео IoT" : "Гео") {
            HStack(spacing: 5) {
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Color.textPrimary)
                Text("±\(stolen ? 180 : 4) м")
                    .font(.system(size: 11))
                    .foregroundColor(Color.muted)
            }
        }
    }

    private var distanceRow: some View {
        infoRow("От вас") {
            if let meters = model.distance(to: scooter) {
                Text(meters < 1000
                     ? "\(Int(meters.rounded())) м"
                     : String(format: "%.2f км", meters / 1000))
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Color.textPrimary)
            } else {
                Text("нужен GPS")
                    .font(.system(size: 11))
                    .foregroundColor(Color.muted)
            }
        }
    }

    private func infoRow<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(Color.muted)
                .lineLimit(2)
                .frame(width: 86, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.panel2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.line, lineWidth: 1))
    }

    @ViewBuilder
    private var warningView: some View {
        if scooter.status == .stolen {
            warningText("Связь с IoT потеряна \(ScooterWorld.ago(minutes: scooter.iotOfflineMinutes)). Координаты — последняя точка, которую успел передать трекер.")
        } else if scooter.status == .lost {
            warningText("ТС помечено как LOST. Ищите по последнему отклику BLE.")
        }
    }

    private func warningText(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("⚠️").font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: 0xF59E0B))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 9)
    }

    private func statusButton(_ status: ScooterStatus) -> some View {
        let current = status == scooter.status
        return Button {
            model.setStatus(status, for: scooter.id)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.color)
                    .frame(width: 9, height: 9)
                Text(status.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                Spacer(minLength: 0)
                if current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(status.color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(current ? status.color.opacity(0.12) : Color.panel2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(current ? status.color : Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
