import AVFoundation
import CoreAudio
import Foundation

/// Default-device routing and diagnostics shared by microphone and system capture.
enum AudioDeviceRouting {
    /// True when the default input routes over Bluetooth (AirPods, etc.). Zoom often
    /// holds exclusive access to that mic during a call, so Ayrvo may fail to start.
    static var defaultInputIsBluetooth: Bool {
        defaultInputTransport == kAudioDeviceTransportTypeBluetooth
    }

    static var defaultOutputIsBluetooth: Bool {
        guard let device = defaultOutputDeviceID else { return false }
        return deviceTransport(device) == kAudioDeviceTransportTypeBluetooth
    }

    /// True when remote audio is likely bleeding into the built-in mic (BT output).
    static var headphoneBleedLikely: Bool {
        defaultOutputIsBluetooth
    }

    static var defaultInputDeviceName: String? {
        guard let device = defaultInputDeviceID else { return nil }
        return deviceName(device)
    }

    static var defaultOutputDeviceName: String? {
        guard let device = defaultOutputDeviceID else { return nil }
        return deviceName(device)
    }

    static func logAudioDeviceSnapshot(context: String) {
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        let micLabel: String = switch micAuth {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown(\(micAuth.rawValue))"
        }
        let sysLabel = SystemAudioPermission.statusLabel
        let input = defaultInputDeviceName ?? "none"
        let output = defaultOutputDeviceName ?? "none"
        let transport = defaultInputTransport.map(transportLabel) ?? "unknown"
        AyrvoConsoleLog.recording(
            "\(context) micTCC=\(micLabel) systemTCC=\(sysLabel) input=[\(input)] transport=\(transport) output=[\(output)]")
    }

    static func deviceName(_ device: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.stride)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr
        else { return nil }
        return name as String
    }

    private static var defaultOutputDeviceID: AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    private static func transportLabel(_ transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "builtIn"
        case kAudioDeviceTransportTypeBluetooth: return "bluetooth"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        default: return "other(\(transport))"
        }
    }

    static var defaultInputDeviceID: AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    private static var defaultInputTransport: UInt32? {
        guard let device = defaultInputDeviceID else { return nil }
        return deviceTransport(device)
    }

    static func deviceTransport(_ device: AudioObjectID) -> UInt32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.stride)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr
        else { return nil }
        return transport
    }

    static func builtInInputDevice() -> AudioObjectID? {
        for device in allInputDevices() {
            guard deviceTransport(device) == kAudioDeviceTransportTypeBuiltIn,
                  let name = deviceName(device),
                  name.localizedCaseInsensitiveContains("microphone")
            else { continue }
            return device
        }
        return allInputDevices().first { deviceTransport($0) == kAudioDeviceTransportTypeBuiltIn }
    }

    private static func allInputDevices() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        var devices = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr
        else { return [] }
        return devices.filter { inputChannelCount($0) > 0 }
    }

    private static func inputChannelCount(_ device: AudioObjectID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0
        else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr
        else { return 0 }
        return Int(raw.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers)
    }

    static func setDefaultInputDevice(_ device: AudioObjectID) throws {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceCopy = device
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.stride), &deviceCopy)
        guard status == noErr else { throw MicRecorderError.inputUnavailable }
    }

    static func restoreDefaultInputDevice(_ device: AudioObjectID) {
        try? setDefaultInputDevice(device)
    }

    static func fourCC(_ code: Int) -> String {
        let v = UInt32(truncatingIfNeeded: code)
        return String(bytes: [
            UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
            UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF),
        ], encoding: .ascii) ?? "?"
    }
}
