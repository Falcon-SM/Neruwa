import SwiftUI
import WeatherKit

/// A cacheable, view-friendly subset of WeatherKit's required attribution.
/// Keeping only URLs and the service name avoids persisting weather models or
/// the location included in their metadata.
struct AmbientWeatherAttribution: Codable, Equatable, Sendable {
    let serviceName: String
    let combinedMarkLightURL: URL
    let combinedMarkDarkURL: URL
    let legalPageURL: URL

    init(_ attribution: WeatherAttribution) {
        serviceName = attribution.serviceName
        combinedMarkLightURL = attribution.combinedMarkLightURL
        combinedMarkDarkURL = attribution.combinedMarkDarkURL
        legalPageURL = attribution.legalPageURL
    }
}

/// Displays the Apple Weather mark and links it to the provider legal page.
/// Insert this wherever a WeatherKit-derived background is visible, and pass
/// nil while the app is using its time-only fallback.
struct WeatherAttributionView: View {
    let attribution: AmbientWeatherAttribution?

    @Environment(\.colorScheme) private var colorScheme

    init(attribution: AmbientWeatherAttribution?) {
        self.attribution = attribution
    }

    @ViewBuilder
    var body: some View {
        if let attribution {
            Link(destination: attribution.legalPageURL) {
                HStack(spacing: 6) {
                    AsyncImage(url: markURL(for: attribution)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 112, maxHeight: 18)
                        case .empty:
                            ProgressView()
                                .controlSize(.mini)
                        case .failure:
                            Text(attribution.serviceName)
                                .font(.caption.weight(.medium))
                        @unknown default:
                            Text(attribution.serviceName)
                                .font(.caption.weight(.medium))
                        }
                    }

                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(attribution.serviceName)のデータ提供元と法的情報")
        }
    }

    private func markURL(for attribution: AmbientWeatherAttribution) -> URL {
        colorScheme == .dark
            ? attribution.combinedMarkDarkURL
            : attribution.combinedMarkLightURL
    }
}
