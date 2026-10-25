import AppKit
import Combine
import CoreLocation

struct WeatherSnapshot: Equatable {
    var temperature: Double
    var high: Double
    var low: Double
    var code: Int
    var isDay: Bool
    var fahrenheit: Bool

    var unitSymbol: String { fahrenheit ? "°F" : "°C" }

    /// SF Symbol for a WMO weather interpretation code (as used by Open-Meteo).
    var symbol: String {
        switch code {
        case 0:            return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:         return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:            return "cloud.fill"
        case 45, 48:       return "cloud.fog.fill"
        case 51...57:      return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86:  return "cloud.snow.fill"
        case 95...99:      return "cloud.bolt.rain.fill"
        default:           return "cloud.fill"
        }
    }

    var summary: String {
        switch code {
        case 0:            return "Clear"
        case 1, 2:         return "Partly cloudy"
        case 3:            return "Cloudy"
        case 45, 48:       return "Fog"
        case 51...57:      return "Drizzle"
        case 61...67, 80...82: return "Rain"
        case 71...77, 85, 86:  return "Snow"
        case 95...99:      return "Thunderstorm"
        default:           return "—"
        }
    }
}

/// Current weather from Open-Meteo (free, no API key) for the Mac's approximate location.
/// Coordinates are rounded to ~1 km before leaving the Mac. Refreshes every 30 minutes and on wake.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    @Published private(set) var weather: WeatherSnapshot?

    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private static let refreshInterval: TimeInterval = 30 * 60

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced

        let settings = AppSettings.shared
        settings.$weatherEnabled
            .combineLatest(settings.$useFahrenheit)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] enabled, _ in
                guard let self else { return }
                if enabled { self.start() } else { self.stop() }
            }
            .store(in: &cancellables)
    }

    private func start() {
        if let lastLocation {
            fetch(for: lastLocation)
        } else {
            requestLocation()
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestLocation() }
        }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.requestLocation() }
            }
        }
    }

    private func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        weather = nil
    }

    private func requestLocation() {
        guard AppSettings.shared.weatherEnabled else { return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }

    private func fetch(for location: CLLocation) {
        let fahrenheit = AppSettings.shared.useFahrenheit
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        guard let url = components.url else { return }

        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
            weather = WeatherSnapshot(
                temperature: payload.current.temperature_2m,
                high: payload.daily.temperature_2m_max.first ?? payload.current.temperature_2m,
                low: payload.daily.temperature_2m_min.first ?? payload.current.temperature_2m,
                code: payload.current.weather_code,
                isDay: payload.current.is_day == 1,
                fahrenheit: fahrenheit
            )
        }
    }

    private struct Payload: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
            self.fetch(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("Shadespace: location unavailable: \(error.localizedDescription)")
    }
}
