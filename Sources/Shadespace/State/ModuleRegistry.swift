import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ModuleRegistry: ObservableObject {
    let nowPlaying: NowPlayingViewModel
    let ai: AIModuleStore
    let fileConverter: FileConverterStore
    let tray: FileTrayStore
    let battery: BatteryMonitor
    let airPods: AirPodsMonitor
    let weather: WeatherService
    private var cancellables = Set<AnyCancellable>()

    init(state: ShadespaceState) {
        self.nowPlaying = NowPlayingViewModel(state: state)
        self.ai = AIModuleStore(state: state)
        self.fileConverter = FileConverterStore(state: state)
        self.tray = FileTrayStore(state: state)
        self.battery = BatteryMonitor(state: state)
        self.airPods = AirPodsMonitor(state: state)
        self.weather = WeatherService()

        // Views observe the registry, so republish every module's changes through it
        let publishers: [ObservableObjectPublisher] = [
            nowPlaying.objectWillChange, ai.objectWillChange, fileConverter.objectWillChange,
            tray.objectWillChange, battery.objectWillChange, weather.objectWillChange,
        ]
        for publisher in publishers {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        nowPlaying.start()
    }

    /// Routes a drop to the module behind the chosen zone. When the zone can't take the file
    /// (e.g. an image on "Summarize") it falls back to the tray, so a drop is never lost.
    func handleDrop(_ providers: [NSItemProvider], zone: DropZone) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        if zone == .tray { return tray.handleDrop(providers: fileProviders) }

        Task {
            guard let url = await FileTrayStore.loadFileURL(from: fileProviders[0]) else { return }
            switch zone {
            case .summarize where AISummarizer.canSummarize(url):
                ai.summarize(url: url)
            case .convert where FileConverterStore.canConvert(url):
                fileConverter.convert(url: url)
            default:
                tray.add([url])
            }
        }
        return true
    }

    /// Which zones make sense for what is being dragged, used to dim the others.
    static func supportedZones(for info: DropInfo) -> Set<DropZone> {
        var zones: Set<DropZone> = [.tray]
        if info.hasItemsConforming(to: [.pdf, .text, .rtf]) { zones.insert(.summarize) }
        if info.hasItemsConforming(to: [.image]) { zones.insert(.convert) }
        return zones
    }
}
