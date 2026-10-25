import Combine
import Foundation

@MainActor
final class ModuleRegistry: ObservableObject {
    let nowPlaying: NowPlayingViewModel
    let ai: AIModuleStore
    let fileConverter: FileConverterStore
    let tray: FileTrayStore
    let battery: BatteryMonitor
    let airPods: AirPodsMonitor
    let weather: WeatherService
    let volume: SystemVolume
    let pomodoro: PomodoroTimer
    private var cancellables = Set<AnyCancellable>()

    init(state: ShadespaceState) {
        self.nowPlaying = NowPlayingViewModel(state: state)
        self.ai = AIModuleStore(state: state)
        self.fileConverter = FileConverterStore(state: state)
        self.tray = FileTrayStore(state: state)
        self.battery = BatteryMonitor(state: state)
        self.airPods = AirPodsMonitor(state: state)
        self.weather = WeatherService()
        self.volume = SystemVolume()
        self.pomodoro = PomodoroTimer(state: state)

        // Views observe the registry, so republish every module's changes through it
        let publishers: [ObservableObjectPublisher] = [
            nowPlaying.objectWillChange, ai.objectWillChange, fileConverter.objectWillChange,
            tray.objectWillChange, battery.objectWillChange, weather.objectWillChange,
            volume.objectWillChange, pomodoro.objectWillChange,
        ]
        for publisher in publishers {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        nowPlaying.start()
    }

    /// Routes dropped files to the module behind the chosen zone. When the zone can't take the
    /// file (e.g. an image on "Summarize") it goes to the tray, so a drop is never lost.
    func handleDrop(_ urls: [URL], zone: DropZone) -> Bool {
        guard let first = urls.first else { return false }
        switch zone {
        case .summarize where AISummarizer.canSummarize(first):
            ai.summarize(url: first)
        case .convert where FileConverterStore.canConvert(first):
            fileConverter.convert(url: first)
        case .airDrop:
            AirDropService.send(urls)
        default:
            tray.add(urls)
        }
        return true
    }

    /// Which zones make sense for the dragged files, used to dim the others.
    static func supportedZones(for urls: [URL]) -> Set<DropZone> {
        var zones: Set<DropZone> = [.tray]
        guard let first = urls.first else { return zones }
        if AirDropService.isAvailable { zones.insert(.airDrop) }
        if AISummarizer.canSummarize(first) { zones.insert(.summarize) }
        if FileConverterStore.canConvert(first) { zones.insert(.convert) }
        return zones
    }
}
