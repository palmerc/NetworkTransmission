//: Playground - noun: a place where people can play

import PlaygroundSupport
import CoreFoundation
import Cocoa

var previousTransitTime: Double?
var jitter: Double = 0
var packetCount: Int = 1

struct Packet {
    let timestamp: timeval
    let sequenceNumber: Int
    let bytes: [UInt8]
}

extension Packet {
    func data() -> Data {
        var packet = self
        let timestampSize = MemoryLayout.stride(ofValue: timestamp)
        let sequenceNumberSize = MemoryLayout.stride(ofValue: sequenceNumber)
        let byteCount = packet.bytes.count * MemoryLayout<UInt8>.stride
        let packetSize = timestampSize + sequenceNumberSize + byteCount
        
        return Data(bytes: &packet, count: packetSize)
    }
}

func getTimeOfDay() -> timeval {
    var time = timeval(tv_sec: 0, tv_usec: 0)
    gettimeofday(&time, nil)
    
    return time
}

func timeOfDayDifference(tv0: timeval, tv1: timeval) -> Double {
    let time1 = Double(tv0.tv_sec) + (Double(tv0.tv_usec) / 1000000.0)
    let time2 = Double(tv1.tv_sec) + (Double(tv1.tv_usec) / 1000000.0)
    var difference = time1 - time2
    if (difference < 0) {
        difference = -difference
    }
    
    return difference
}

func updateJitter(sent: timeval, received: timeval) -> Double {
    let transitTime = timeOfDayDifference(tv0: sent, tv1: received)
    if let ptt = previousTransitTime {
        var difference = transitTime - ptt
        if (difference < 0) {
            difference = -difference
        }
        jitter += (difference - jitter) / 16.0
    }
    previousTransitTime = transitTime

    return jitter
}

extension Data
{
    static func random(count: Int) -> [UInt8] {
        let bytes = [UInt8](repeating: 0, count: count).map { _ in UInt8(arc4random_uniform(255)) }
        return bytes
    }
}

let packetSize = 1024
let packetHeaderSize = MemoryLayout<timeval>.size + MemoryLayout<Int>.size
let randomData = Data.random(count: packetSize - packetHeaderSize)

let connection1 = UDPServerConnection()
connection1.debugName = "Connection 1"
connection1.bindUDP(host: "0.0.0.0", port: 0)
let udpPort1 = connection1.port

let connection2 = UDPServerConnection()
connection2.debugName = "Connection 2"
connection2.bindUDP(host: "0.0.0.0", port: 0)
let udpPort2 = connection2.port

connection1.receiveHandler = {
    (datagram: Data) in
    let packet = datagram.withUnsafeBytes({
        (ptr: UnsafePointer<Packet>) -> Packet in
        return ptr.pointee
    })
    updateJitter(sent: packet.timestamp, received: getTimeOfDay())
    print("Packet: \(packet.sequenceNumber), Jitter: \(jitter)")
    connection1.send(data: datagram, host: "127.0.0.1", port: udpPort2)
}
connection2.receiveHandler = {
    (datagram: Data) in
    
    var packet = Packet(timestamp: getTimeOfDay(), sequenceNumber: packetCount, bytes: randomData)
    let data = Data(bytes: &packet, count: packetSize)
    connection2.send(data: data, host: "127.0.0.1", port: udpPort1)
    
    packetCount += 1
}

var packet = Packet(timestamp: getTimeOfDay(), sequenceNumber: packetCount, bytes: randomData)
connection1.send(data: packet.data(), host: "127.0.0.1", port: udpPort2)

PlaygroundPage.current.needsIndefiniteExecution = true
