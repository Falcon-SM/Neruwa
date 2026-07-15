import Combine
@preconcurrency import CoreLocation
import Foundation
import WeatherKit

/// The small set of visual states the ambient background knows how to draw.
/// WeatherKit models never leak into the view layer, which also gives previews
/// and offline use a deterministic time-only fallback.
enum AmbientScene: String, Codable, Equatable, Sendable {
    case night
    case morning
    case clear
    case cloudy
    case rain
    case snow
    case storm
    case fog

    var isNight: Bool {
        self == .night
    }

    static func timeFallback(
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> AmbientScene {
        switch calendar.component(.hour, from: date) {
        case 5..<9:
            .morning
        case 9..<19:
            .clear
        default:
            .night
        }
    }
}

enum AmbientWeatherSource: Equatable, Sendable {
    case time
    case cachedWeather
    case liveWeather
}

enum AmbientWeatherStatus: Equatable, Sendable {
    case disabled
    case needsPermission
    case requestingPermission
    case permissionDenied
    case restricted
    case loading
    case live
    case cached
    case unavailable

    var message: String {
        switch self {
        case .disabled:
            "時刻に合わせた背景を使用中"
        case .needsPermission:
            "現在地を許可すると、天気を背景に反映できます"
        case .requestingPermission:
            "位置情報の許可を確認しています"
        case .permissionDenied:
            "位置情報が許可されていないため、時刻に合わせています"
        case .restricted:
            "この端末では位置情報を利用できません"
        case .loading:
            "現在地付近の天気を確認しています"
        case .live:
            "現在地付近の天気を背景に反映中"
        case .cached:
            "前回取得した天気を背景に反映中"
        case .unavailable:
            "天気を取得できないため、時刻に合わせています"
        }
    }

    var systemImage: String {
        switch self {
        case .disabled:
            "clock"
        case .needsPermission, .requestingPermission:
            "location"
        case .permissionDenied, .restricted:
            "location.slash"
        case .loading:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .live:
            "location.fill"
        case .cached:
            "clock.arrow.circlepath"
        case .unavailable:
            "wifi.exclamationmark"
        }
    }
}

@MainActor
final class AmbientEnvironmentStore: NSObject, ObservableObject {
    private enum DefaultsKey {
        static let weatherEnabled = "ambient.weather.enabled.v1"
        static let weatherCache = "ambient.weather.cache.v1"
    }

    fileprivate enum Timing {
        static let oldestAcceptedLocation: TimeInterval = 60 * 60
    }

    @Published private(set) var scene: AmbientScene
    @Published private(set) var weatherEnabled: Bool
    @Published private(set) var weatherStatus: AmbientWeatherStatus
    @Published private(set) var weatherSource: AmbientWeatherSource = .time
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var attribution: AmbientWeatherAttribution?
    @Published private(set) var lastErrorMessage: String?

    /// True only while the visible scene is derived from WeatherKit data.
    /// Use this to decide whether the required attribution should be visible.
    var usesWeatherData: Bool {
        weatherSource != .time && attribution != nil
    }

    private let defaults: UserDefaults
    private let locationManager: CLLocationManager
    private var cachedWeather: AmbientWeatherCache?
    private var weatherTask: Task<Void, Never>?
    private var isLocationRequestInFlight = false
    private var isWaitingForUserAuthorization = false

    init(defaults: UserDefaults = .standard) {
        let manager = CLLocationManager()
        let isEnabled = defaults.bool(forKey: DefaultsKey.weatherEnabled)

        self.defaults = defaults
        self.locationManager = manager
        self.scene = .timeFallback()
        self.weatherEnabled = isEnabled
        self.weatherStatus = isEnabled ? .needsPermission : .disabled
        self.authorizationStatus = manager.authorizationStatus

        super.init()

        manager.delegate = self
        // City-level accuracy is enough for a decorative weather background.
        // Reduced Accuracy authorization is also accepted; full accuracy is
        // never requested.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer

        restoreCachedWeather()
        reconcileAuthorizationWithoutPrompting()
    }

    /// Call this only from a direct user interaction such as a Settings toggle.
    /// This is the sole API that can present the system location permission UI.
    func enableWeatherFromUserAction() {
        weatherEnabled = true
        defaults.set(true, forKey: DefaultsKey.weatherEnabled)
        lastErrorMessage = nil

        switch locationManager.authorizationStatus {
        case .notDetermined:
            isWaitingForUserAuthorization = true
            weatherStatus = .requestingPermission
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            refreshIfNeeded(force: true)
        case .denied:
            applyTimeFallback(status: .permissionDenied)
        case .restricted:
            applyTimeFallback(status: .restricted)
        @unknown default:
            applyTimeFallback(status: .unavailable)
        }
    }

    /// Convenience API for a SwiftUI Toggle. Enabling must still originate in
    /// that toggle's user action; background lifecycle code should call
    /// `refreshIfNeeded()` instead.
    func setWeatherEnabledFromUserAction(_ enabled: Bool) {
        if enabled {
            enableWeatherFromUserAction()
        } else {
            disableWeather()
        }
    }

    func disableWeather() {
        weatherEnabled = false
        defaults.set(false, forKey: DefaultsKey.weatherEnabled)
        defaults.removeObject(forKey: DefaultsKey.weatherCache)

        weatherTask?.cancel()
        weatherTask = nil
        locationManager.stopUpdatingLocation()
        isLocationRequestInFlight = false
        isWaitingForUserAuthorization = false
        isRefreshing = false
        cachedWeather = nil
        attribution = nil
        lastUpdatedAt = nil
        lastErrorMessage = nil
        applyTimeFallback(status: .disabled)
    }

    /// Safe to call on launch and whenever the app returns to the foreground.
    /// It never asks for permission. A request is made only when authorization
    /// already exists and the small cached snapshot has expired.
    func refreshIfNeeded(force: Bool = false, now: Date = .now) {
        updateForCurrentTime(now: now)

        guard weatherEnabled else {
            weatherStatus = .disabled
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if !force,
               let cachedWeather,
               cachedWeather.isFresh(at: now),
               !cachedWeather.hasCrossedVisualPeriod(at: now) {
                applyCachedWeather(cachedWeather, at: now)
                return
            }
            requestOneLocation()
        case .notDetermined:
            // Privacy prompt is deliberately reserved for
            // `enableWeatherFromUserAction()`.
            applyTimeFallback(status: .needsPermission, now: now)
        case .denied:
            applyTimeFallback(status: .permissionDenied, now: now)
        case .restricted:
            applyTimeFallback(status: .restricted, now: now)
        @unknown default:
            applyTimeFallback(status: .unavailable, now: now)
        }
    }

    /// The next clock boundary that can change the scene, capped by the
    /// WeatherKit snapshot's expiration so expired data is never left visible.
    func nextAutomaticRefreshDate(after date: Date = .now) -> Date {
        let nextHour = Calendar.current.nextDate(
            after: date,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(60 * 60)

        guard weatherEnabled,
              let cachedWeather,
              cachedWeather.isFresh(at: date) else {
            return nextHour
        }
        return min(nextHour, cachedWeather.expirationDate)
    }

    /// Re-resolves the visible scene without touching Core Location or the
    /// network. This is useful on scene-phase changes and date boundaries.
    func updateForCurrentTime(now: Date = .now) {
        guard weatherEnabled,
              isAuthorized,
              let cachedWeather,
              cachedWeather.isFresh(at: now),
              !cachedWeather.hasCrossedVisualPeriod(at: now),
              cachedWeather.attribution != nil else {
            scene = .timeFallback(at: now)
            weatherSource = .time
            if !weatherEnabled {
                weatherStatus = .disabled
            }
            return
        }

        scene = cachedWeather.resolvedScene(at: now)
        attribution = cachedWeather.attribution
        lastUpdatedAt = cachedWeather.fetchedAt
        weatherSource = .cachedWeather
        weatherStatus = .cached
    }

    private var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            true
        default:
            false
        }
    }

    private func restoreCachedWeather() {
        guard let data = defaults.data(forKey: DefaultsKey.weatherCache),
              let decoded = try? JSONDecoder().decode(AmbientWeatherCache.self, from: data) else {
            return
        }

        cachedWeather = decoded
        guard weatherEnabled,
              isAuthorized,
              decoded.isFresh(at: .now),
              !decoded.hasCrossedVisualPeriod(at: .now),
              decoded.attribution != nil else {
            return
        }

        applyCachedWeather(decoded, at: .now)
    }

    private func reconcileAuthorizationWithoutPrompting() {
        authorizationStatus = locationManager.authorizationStatus

        guard weatherEnabled else {
            weatherStatus = .disabled
            return
        }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if cachedWeather == nil {
                weatherStatus = .unavailable
            }
        case .notDetermined:
            applyTimeFallback(status: .needsPermission)
        case .denied:
            applyTimeFallback(status: .permissionDenied)
        case .restricted:
            applyTimeFallback(status: .restricted)
        @unknown default:
            applyTimeFallback(status: .unavailable)
        }
    }

    private func requestOneLocation() {
        guard !isLocationRequestInFlight, weatherTask == nil else { return }

        isLocationRequestInFlight = true
        isRefreshing = true
        weatherStatus = .loading
        lastErrorMessage = nil
        locationManager.requestLocation()
    }

    private func fetchCurrentWeather(for location: CLLocation) {
        guard weatherEnabled else { return }

        weatherTask?.cancel()
        weatherTask = Task { [weak self] in
            guard let self else { return }

            do {
                let current = try await WeatherService.shared.weather(
                    for: location,
                    including: .current
                )

                let resolvedAttribution: AmbientWeatherAttribution
                if let attribution = self.attribution {
                    resolvedAttribution = attribution
                } else {
                    let provider = try await WeatherService.shared.attribution
                    resolvedAttribution = AmbientWeatherAttribution(provider)
                }

                try Task.checkCancellation()
                self.applyLiveWeather(current, attribution: resolvedAttribution)
            } catch is CancellationError {
                self.isRefreshing = false
                self.weatherTask = nil
            } catch {
                self.handleWeatherFailure()
            }
        }
    }

    private func applyLiveWeather(
        _ current: CurrentWeather,
        attribution: AmbientWeatherAttribution,
        now: Date = .now
    ) {
        guard weatherEnabled else {
            isRefreshing = false
            weatherTask = nil
            return
        }

        let providerExpiration = current.metadata.expirationDate
        let snapshot = AmbientWeatherCache(
            family: AmbientConditionFamily(current.condition),
            isDaylight: current.isDaylight,
            fetchedAt: now,
            expirationDate: max(providerExpiration, now),
            attribution: attribution
        )

        cachedWeather = snapshot
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: DefaultsKey.weatherCache)
        }

        scene = snapshot.resolvedScene(at: now)
        weatherSource = .liveWeather
        weatherStatus = .live
        lastUpdatedAt = now
        self.attribution = attribution
        lastErrorMessage = nil
        isRefreshing = false
        weatherTask = nil
    }

    private func applyCachedWeather(_ cache: AmbientWeatherCache, at date: Date) {
        guard let attribution = cache.attribution else {
            applyTimeFallback(status: .unavailable, now: date)
            return
        }

        scene = cache.resolvedScene(at: date)
        weatherSource = .cachedWeather
        weatherStatus = .cached
        lastUpdatedAt = cache.fetchedAt
        self.attribution = attribution
    }

    private func handleWeatherFailure(now: Date = .now) {
        weatherTask = nil
        isRefreshing = false

        guard weatherEnabled else {
            applyTimeFallback(status: .disabled, now: now)
            return
        }

        lastErrorMessage = "現在地付近の天気を取得できませんでした。"

        if let cachedWeather,
           cachedWeather.isFresh(at: now),
           !cachedWeather.hasCrossedVisualPeriod(at: now),
           cachedWeather.attribution != nil {
            applyCachedWeather(cachedWeather, at: now)
        } else {
            applyTimeFallback(status: .unavailable, now: now)
        }
    }

    private func applyTimeFallback(
        status: AmbientWeatherStatus,
        now: Date = .now
    ) {
        scene = .timeFallback(at: now)
        weatherSource = .time
        weatherStatus = status
        attribution = nil
        lastUpdatedAt = nil
        isRefreshing = false
    }
}

extension AmbientEnvironmentStore: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let previousStatus = authorizationStatus
        authorizationStatus = manager.authorizationStatus

        guard weatherEnabled else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            let wasWaitingForUser = isWaitingForUserAuthorization
            isWaitingForUserAuthorization = false
            if wasWaitingForUser || previousStatus != manager.authorizationStatus {
                refreshIfNeeded(force: true)
            }
        case .notDetermined:
            if isWaitingForUserAuthorization {
                weatherStatus = .requestingPermission
            } else {
                applyTimeFallback(status: .needsPermission)
            }
        case .denied:
            isWaitingForUserAuthorization = false
            applyTimeFallback(status: .permissionDenied)
        case .restricted:
            isWaitingForUserAuthorization = false
            applyTimeFallback(status: .restricted)
        @unknown default:
            isWaitingForUserAuthorization = false
            applyTimeFallback(status: .unavailable)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        isLocationRequestInFlight = false

        guard weatherEnabled else { return }

        let now = Date()
        guard let location = locations.last(where: { candidate in
            candidate.horizontalAccuracy >= 0
                && abs(candidate.timestamp.timeIntervalSince(now)) <= Timing.oldestAcceptedLocation
        }) else {
            handleWeatherFailure(now: now)
            return
        }

        fetchCurrentWeather(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocationRequestInFlight = false
        guard weatherEnabled else { return }
        handleWeatherFailure()
    }
}

private enum AmbientConditionFamily: String, Codable, Sendable {
    case clear
    case cloudy
    case rain
    case snow
    case storm
    case fog

    init(_ condition: WeatherCondition) {
        switch condition {
        case .clear, .mostlyClear, .hot:
            self = .clear
        case .cloudy, .mostlyCloudy, .partlyCloudy, .breezy, .windy:
            self = .cloudy
        case .drizzle, .freezingDrizzle, .freezingRain, .heavyRain, .rain, .sunShowers:
            self = .rain
        case .blizzard, .blowingSnow, .flurries, .frigid, .hail, .heavySnow,
             .sleet, .snow, .sunFlurries, .wintryMix:
            self = .snow
        case .hurricane, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .thunderstorms, .tropicalStorm:
            self = .storm
        case .blowingDust, .foggy, .haze, .smoky:
            self = .fog
        @unknown default:
            self = .cloudy
        }
    }

    var scene: AmbientScene {
        switch self {
        case .clear: .clear
        case .cloudy: .cloudy
        case .rain: .rain
        case .snow: .snow
        case .storm: .storm
        case .fog: .fog
        }
    }
}

private struct AmbientWeatherCache: Codable, Sendable {
    let family: AmbientConditionFamily
    let isDaylight: Bool
    let fetchedAt: Date
    let expirationDate: Date
    let attribution: AmbientWeatherAttribution?

    func isFresh(at date: Date) -> Bool {
        date < expirationDate
    }

    func hasCrossedVisualPeriod(at date: Date) -> Bool {
        AmbientScene.timeFallback(at: fetchedAt) != AmbientScene.timeFallback(at: date)
    }

    func resolvedScene(at date: Date) -> AmbientScene {
        guard isDaylight else { return .night }

        let fallback = AmbientScene.timeFallback(at: date)
        if family == .clear, fallback == .morning {
            return .morning
        }
        return family.scene
    }
}
