import AudioToolbox
import CoreAudio
import Foundation

/// Output volume of the current default audio device (speakers, AirPods, display…).
/// Listens to CoreAudio property changes, so keyboard volume keys update it too.
@MainActor
final class SystemVolume: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    /// False for devices whose volume can't be set (e.g. some HDMI outputs).
    @Published private(set) var isAdjustable = false

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private let listenerQueue = DispatchQueue(label: "shadespace.volume")
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.attachToDefaultDevice() }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &Self.defaultDeviceAddress, listenerQueue, listener)
        attachToDefaultDevice()
    }

    func setVolume(_ value: Float) {
        guard isAdjustable else { return }
        var level = min(max(value, 0), 1)
        volume = level
        AudioObjectSetPropertyData(deviceID, &Self.volumeAddress, 0, nil,
                                   UInt32(MemoryLayout<Float32>.size), &level)
        if isMuted, level > 0 { setMuted(false) }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    // MARK: - Private

    private func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(deviceID, &Self.muteAddress, 0, nil,
                                                UInt32(MemoryLayout<UInt32>.size), &value)
        if status == noErr { isMuted = muted }
    }

    /// Follows the default output: switching to AirPods moves the listeners to them.
    private func attachToDefaultDevice() {
        if let volumeListener, deviceID != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.volumeAddress, listenerQueue, volumeListener)
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.muteAddress, listenerQueue, volumeListener)
        }

        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress,
                                   0, nil, &size, &id)
        deviceID = id

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.read() }
        }
        volumeListener = listener
        AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, listenerQueue, listener)
        AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, listenerQueue, listener)
        read()
    }

    private func read() {
        var settable: DarwinBoolean = false
        isAdjustable = AudioObjectHasProperty(deviceID, &Self.volumeAddress)
            && AudioObjectIsPropertySettable(deviceID, &Self.volumeAddress, &settable) == noErr
            && settable.boolValue

        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(deviceID, &Self.volumeAddress, 0, nil, &size, &level) == noErr {
            volume = level
        }

        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(deviceID, &Self.muteAddress),
           AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &size, &muted) == noErr {
            isMuted = muted != 0
        } else {
            isMuted = false
        }
    }
}
