// TemperatureSampler.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Darwin
import Foundation

/// 通过 IOHID 事件系统读取温度传感器（与 Raycast temperature-reader 同源思路）
///
/// 符号不在公开头文件里，用 `dlsym` 动态解析；失败时仍回落 `ProcessInfo.thermalState`。
enum TemperatureSampler {

    nonisolated static func sample(thermalState: ProcessInfo.ThermalState) -> TemperatureSnapshot {
        let stateLabel = TemperatureParsing.thermalStateLabel(thermalState)
        let sensors = readHIDSensors()
        return TemperatureParsing.aggregate(sensors: sensors, thermalStateLabel: stateLabel)
    }

    // MARK: - HID

    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias ClientSetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias ClientCopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias ServiceCopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias ServiceCopyEvent =
        @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias EventGetFloat = @convention(c) (AnyObject, Int32) -> Double

    nonisolated private static func readHIDSensors() -> [TemperatureSensor] {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return []
        }
        defer { dlclose(handle) }

        guard
            let createSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
            let matchSym = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
            let servicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
            let propertySym = dlsym(handle, "IOHIDServiceClientCopyProperty"),
            let eventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
            let floatSym = dlsym(handle, "IOHIDEventGetFloatValue")
        else {
            return []
        }

        let create = unsafeBitCast(createSym, to: ClientCreate.self)
        let setMatching = unsafeBitCast(matchSym, to: ClientSetMatching.self)
        let copyServices = unsafeBitCast(servicesSym, to: ClientCopyServices.self)
        let copyProperty = unsafeBitCast(propertySym, to: ServiceCopyProperty.self)
        let copyEvent = unsafeBitCast(eventSym, to: ServiceCopyEvent.self)
        let getFloat = unsafeBitCast(floatSym, to: EventGetFloat.self)

        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return [] }

        let matching: [String: Int] = [
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 5
        ]
        _ = setMatching(client, matching as CFDictionary)

        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else {
            return []
        }

        // kIOHIDEventTypeTemperature = 15；字段基址 = type << 16
        let eventType: Int64 = 15
        let fieldBase = Int32(15 << 16)

        var map: [String: Double] = [:]
        for service in services {
            guard let nameRef = copyProperty(service, "Product" as CFString)?.takeRetainedValue(),
                let name = nameRef as? String
            else { continue }
            guard let event = copyEvent(service, eventType, 0, 0)?.takeRetainedValue() else { continue }
            let temp = getFloat(event, fieldBase)
            if temp > 0, temp < 130 {
                map[name] = (temp * 10).rounded() / 10
            }
        }

        return map.map { name, temp in
            TemperatureSensor(
                name: name,
                label: TemperatureParsing.label(forRawName: name),
                celsius: temp
            )
        }
    }
}
