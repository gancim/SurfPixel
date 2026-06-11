import CoreBluetooth
import Foundation
import os

let log = Logger(subsystem: "com.gancim.surfpixel", category: "app")

/// Talks to an iDotMatrix display over Bluetooth LE.
///
/// Protocol (reverse-engineered, same as the python3-idotmatrix-library):
///  - device advertises a name starting with "IDM-"
///  - commands are written to characteristic FA02 without response
///  - enter DIY mode: [5, 0, 4, 1, 1]
///  - set brightness: [5, 0, 4, 128, percent]
///  - image: PNG bytes split in 4096-byte chunks, each prefixed with
///    int16le(pngLen + chunkCount), [0, 0, first ? 0 : 2], int32le(pngLen)
final class MatrixDevice: NSObject {
    private static let writeUUID = CBUUID(string: "FA02")
    private static let peripheralKey = "lastPeripheralIdentifier"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var pendingMessages: [Data] = []  // full messages awaiting a connection
    private var sendQueue: [Data] = []        // MTU-sized chunks being written

    var namePrefix = "IDM-"
    var onStatus: ((String) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Queue a full update (brightness + DIY mode + frame) and deliver it as
    /// soon as the device is reachable.
    func push(frame png: Data, brightness: Int) {
        let level = UInt8(min(100, max(5, brightness)))
        pendingMessages = [
            Data([5, 0, 4, 128, level]),
            Data([5, 0, 4, 1, 1]),
            Self.imagePayload(png),
        ]
        log.info("push requested: frame \(png.count) bytes, brightness \(level)")
        deliver()
    }

    static func imagePayload(_ png: Data) -> Data {
        let chunkSize = 4096
        var chunks: [Data] = []
        var i = 0
        while i < png.count {
            chunks.append(png.subdata(in: i..<min(i + chunkSize, png.count)))
            i += chunkSize
        }
        var out = Data()
        let header16 = UInt16(png.count + chunks.count).littleEndian
        let len32 = UInt32(png.count).littleEndian
        for (n, chunk) in chunks.enumerated() {
            withUnsafeBytes(of: header16) { out.append(contentsOf: $0) }
            out.append(contentsOf: [0, 0, n > 0 ? 2 : 0])
            withUnsafeBytes(of: len32) { out.append(contentsOf: $0) }
            out.append(chunk)
        }
        return out
    }

    // MARK: - connection / delivery

    private func deliver() {
        guard !pendingMessages.isEmpty else { return }
        guard central.state == .poweredOn else {
            log.warning("cannot deliver: bluetooth state \(self.central.state.rawValue)")
            onStatus?(statusText(for: central.state))
            return
        }
        if let p = peripheral, p.state == .connected, writeChar != nil {
            log.info("device already connected, sending")
            enqueueAndPump()
            return
        }
        // try the device we paired with before, otherwise scan by name
        if peripheral == nil,
           let saved = UserDefaults.standard.string(forKey: Self.peripheralKey),
           let uuid = UUID(uuidString: saved),
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            peripheral = known
        }
        if let p = peripheral {
            log.info("connecting to known peripheral \(p.identifier)")
            onStatus?("connecting…")
            central.connect(p)
        } else {
            log.info("no known peripheral, scanning")
            onStatus?("scanning…")
            central.scanForPeripherals(withServices: nil)
        }
    }

    private func enqueueAndPump() {
        guard let p = peripheral else { return }
        let mtu = p.maximumWriteValueLength(for: .withoutResponse)
        for msg in pendingMessages {
            var i = 0
            while i < msg.count {
                sendQueue.append(msg.subdata(in: i..<min(i + mtu, msg.count)))
                i += mtu
            }
        }
        pendingMessages = []
        pump()
    }

    private func pump() {
        guard let p = peripheral, let ch = writeChar else { return }
        while !sendQueue.isEmpty && p.canSendWriteWithoutResponse {
            p.writeValue(sendQueue.removeFirst(), for: ch, type: .withoutResponse)
        }
        if sendQueue.isEmpty {
            log.info("frame fully written to device")
            onStatus?("updated")
        }
    }

    private func statusText(for state: CBManagerState) -> String {
        switch state {
        case .unauthorized: return "Bluetooth permission denied"
        case .poweredOff: return "Bluetooth is off"
        case .unsupported: return "Bluetooth unsupported"
        default: return "waiting for Bluetooth…"
        }
    }
}

extension MatrixDevice: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            deliver()
        } else {
            writeChar = nil
            onStatus?(statusText(for: central.state))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        guard name.hasPrefix(namePrefix) else { return }
        central.stopScan()
        self.peripheral = peripheral
        onStatus?("connecting to \(name)…")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.peripheralKey)
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        self.peripheral = nil
        onStatus?("connection failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log.info("device disconnected: \(error?.localizedDescription ?? "clean")")
        writeChar = nil
        sendQueue = []
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([Self.writeUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == Self.writeUUID })
        else { return }
        writeChar = ch
        enqueueAndPump()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pump()
    }
}
