import Foundation

/// A object containing a sockaddr_in6 structure.
class SocketAddress6 {
    
    // MARK: Properties
    
    /// The sockaddr_in6 structure.
    var sin6: sockaddr_in6
    
    /// The IPv6 address as a string.
    var stringValue: String? {
        return withUnsafePointer(to: &sin6) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { saToString($0) } }
    }
    
    // MARK: Initializers
    
    init() {
        sin6 = sockaddr_in6()
        sin6.sin6_len = __uint8_t(MemoryLayout<sockaddr_in6>.size)
        sin6.sin6_family = sa_family_t(AF_INET6)
        sin6.sin6_port = in_port_t(0)
        sin6.sin6_addr = in6addr_any
        sin6.sin6_scope_id = __uint32_t(0)
        sin6.sin6_flowinfo = __uint32_t(0)
    }
    
    convenience init(otherAddress: SocketAddress6) {
        self.init()
        sin6 = otherAddress.sin6
    }
    
    /// Set the IPv6 address from a string.
    func setFromString(_ str: String) -> Bool {
        return str.withCString({ cs in inet_pton(AF_INET6, cs, &sin6.sin6_addr) }) == 1
    }
    
    /// Set the port.
    func setPort(_ port: Int) {
        sin6.sin6_port = in_port_t(UInt16(port).bigEndian)
    }
}

/// An object containing a sockaddr_in structure.
class SocketAddress {
    
    // MARK: Properties
    
    /// The sockaddr_in structure.
    var sin: sockaddr_in
    
    /// The IPv4 address in string form.
    var stringValue: String? {
        return withUnsafePointer(to: &sin) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { saToString($0) } }
    }
    
    // MARK: Initializers
    
    init() {
        sin = sockaddr_in(sin_len:__uint8_t(MemoryLayout<sockaddr_in>.size), sin_family:sa_family_t(AF_INET), sin_port:in_port_t(0), sin_addr:in_addr(s_addr: 0), sin_zero:(Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0)))
    }
    
    convenience init(otherAddress: SocketAddress) {
        self.init()
        sin = otherAddress.sin
    }
    
    /// Set the IPv4 address from a string.
    func setFromString(_ str: String) -> Bool {
        return str.withCString({ cs in inet_pton(AF_INET, cs, &sin.sin_addr) }) == 1
    }
    
    /// Set the port.
    func setPort(_ port: Int) {
        sin.sin_port = in_port_t(UInt16(port).bigEndian)
    }
    
    /// Increment the address by a given amount.
    func increment(_ amount: UInt32) {
        let networkAddress = sin.sin_addr.s_addr.byteSwapped + amount
        sin.sin_addr.s_addr = networkAddress.byteSwapped
    }
    
    /// Get the difference between this address and another address.
    func difference(_ otherAddress: SocketAddress) -> Int64 {
        return Int64(sin.sin_addr.s_addr.byteSwapped - otherAddress.sin.sin_addr.s_addr.byteSwapped)
    }
}

// MARK: Utility Functions

/// Convert a sockaddr structure to a string.
func saToString(_ sa: UnsafePointer<sockaddr>) -> String? {
    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    var portBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))
    
    guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostBuffer, socklen_t(hostBuffer.count), &portBuffer, socklen_t(portBuffer.count), NI_NUMERICHOST | NI_NUMERICSERV) == 0
        else { return nil }
    
    return String(cString: hostBuffer)
}

