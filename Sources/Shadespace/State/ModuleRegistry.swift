import Foundation

@MainActor
final class ModuleRegistry: ObservableObject {
    let nowPlaying: NowPlayingViewModel
    let clipboard: ClipboardStore
    let stats: SystemStatsMonitor
    let focus: FocusController
    let ai: AIModuleStore

    init(state: ShadespaceState) {
        self.nowPlaying = NowPlayingViewModel(state: state)
        self.clipboard = ClipboardStore()
        self.stats = SystemStatsMonitor()
        self.focus = FocusController()
        self.ai = AIModuleStore()

        nowPlaying.start()
        clipboard.start()
    }

    func setExpanded(_ expanded: Bool) {
        if expanded { stats.start() } else { stats.stop() }
    }
}
