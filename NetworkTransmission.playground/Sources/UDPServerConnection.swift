import Foundation
import Darwin



public class UDPServerConnection
{
    /// The address family of the UDP socket.
    var addressFamily: Int32 = AF_UNSPEC
    public var debugName: String? = ""
    public var port: Int = 0
    public var receiveHandler: ((_ datagram: Data) -> ())?
    
    /// A dispatch source for reading data from the UDP socket.
    var responseSource: DispatchSourceRead?
    
    public init(withReceiveHandler receiveHandler: ((_ datagram: Data) -> ())?)
    {
        self.receiveHandler = receiveHandler
    }
    
    public convenience init() {
        self.init(withReceiveHandler: nil)
    }
    
    deinit
    {
        responseSource?.cancel()
    }
    
    
    /// Create a UDP socket
    public func createSocket(address: String) -> Bool
    {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        var newSocket: Int32 = -1
        
        if address.withCString({ cstring in inet_pton(AF_INET6, cstring, &sin6.sin6_addr) }) == 1 {
            // IPv6 peer.
            newSocket = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
            addressFamily = AF_INET6
        } else if address.withCString({ cstring in inet_pton(AF_INET, cstring, &sin.sin_addr) }) == 1 {
            // IPv4 peer.
            newSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            addressFamily = AF_INET
        }
        
        guard newSocket > 0 else { return false }
        
        let newResponseSource = DispatchSource.makeReadSource(fileDescriptor: newSocket, queue: .main)
        
        newResponseSource.setCancelHandler {
            print("setCancelHandler")
            let UDPSocket = Int32(newResponseSource.handle)
            close(UDPSocket)
        }
        
        newResponseSource.setEventHandler {
            guard let source = self.responseSource else { return }
            
            var socketAddress = sockaddr_storage()
            var socketAddressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            var response = [UInt8](repeating: 0, count: 4096)
            let UDPSocket = Int32(source.handle)
            
            let bytesRead = withUnsafeMutablePointer(to: &socketAddress, {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(UDPSocket, UnsafeMutableRawPointer(&response), response.count, 0, $0, UnsafeMutablePointer<socklen_t>(&socketAddressLength))
                }
            })
            
            guard bytesRead >= 0 else {
                if let errorString = String(utf8String: strerror(errno)) {
                    print("recvfrom failed: \(errorString)")
                }
                //                self.closeConnection(.all)
                return
            }
            
            guard bytesRead > 0 else {
                print("recvfrom returned EOF")
                close(UDPSocket)
                return
            }
            
            guard let endpoint = withUnsafePointer(to: &socketAddress, {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    self.getEndpointInfo(socketAddressPointer: $0)
                }
            }) else {
                print("Failed to get the address and port from the socket address received from recvfrom")
                close(UDPSocket)
                return
            }
            
            let bytes = UnsafeRawPointer(response)
            let responseDatagram = Data(bytes: bytes, count: bytesRead)
            var connectionName = ""
            if let debugName = self.debugName {
                connectionName = debugName
            }
            print("UDP connection \(connectionName) received = \(bytesRead) bytes from host = \(endpoint.host) port = \(endpoint.port)")
            if let receiveHandler = self.receiveHandler {
                receiveHandler(responseDatagram)
            }
        }
        
        newResponseSource.resume()
        self.responseSource = newResponseSource
        
        return true
    }
    
    public func bindUDP(host: String, port: Int)
    {
        if responseSource == nil {
            guard createSocket(address: host) else {
                print("UDP ServerConnection initialization failed.")
                return
            }
        }
        
        guard let source = responseSource else { return }
        let UDPSocket = Int32(source.handle)
        var code: Int32 = 0
        
        switch addressFamily {
        case AF_INET:
            let serverAddress = SocketAddress()
            guard serverAddress.setFromString(host) else {
                print("Failed to convert \(host) into an IPv4 address")
                return
            }
            serverAddress.setPort(port)
            
            code = withUnsafePointer(to: &serverAddress.sin) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    let sockLength = socklen_t(serverAddress.sin.sin_len)
                    return bind(UDPSocket, $0, sockLength)
                }
            }
            
            withUnsafeMutablePointer(to: &serverAddress.sin) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    var sockLength = socklen_t(serverAddress.sin.sin_len)
                    if (getsockname(UDPSocket, $0, UnsafeMutablePointer(&sockLength)) < 0) {
                        print("Bad things happened.")
                    }
                    
                    if let values = getEndpointInfo(socketAddressPointer: $0) {
                        self.port = values.port
                    }
                }
            }
            
        case AF_INET6:
            let serverAddress6 = SocketAddress6()
            guard serverAddress6.setFromString(host) else {
                print("Failed to convert \(host) into an IPv6 address")
                return
            }
            serverAddress6.setPort(port)
            
            code = withUnsafePointer(to: &serverAddress6.sin6) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    let sockLength = socklen_t(serverAddress6.sin6.sin6_len)
                    return bind(UDPSocket, $0, sockLength)
                }
            }
            
            withUnsafeMutablePointer(to: &serverAddress6.sin6) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    var sockLength = socklen_t(serverAddress6.sin6.sin6_len)
                    if (getsockname(UDPSocket, $0, UnsafeMutablePointer(&sockLength)) < 0) {
                        print("Bad things happened.")
                    }
                    
                    if let values = getEndpointInfo(socketAddressPointer: $0) {
                        self.port = values.port
                    }
                }
            }
            
        default:
            return
        }
        
        print("Code \(code)")
    }
    
    public func closeUDP()
    {
        guard let source = responseSource else { return }
        let UDPSocket = Int32(source.handle)
        
        close(UDPSocket)
    }
    
    /// Send a datagram to a given host and port.
    public func send(data: Data, host: String, port: Int)
    {
        if responseSource == nil {
            guard createSocket(address: host) else {
                print("UDP ServerConnection initialization failed.")
                return
            }
        }
        
        guard let source = responseSource else { return }
        let UDPSocket = Int32(source.handle)
        var sent = 0
        
        switch addressFamily {
        case AF_INET:
            let serverAddress = SocketAddress()
            guard serverAddress.setFromString(host) else {
                print("Failed to convert \(host) into an IPv4 address")
                return
            }
            serverAddress.setPort(port)
            
            data.withUnsafeBytes {
                (bytes: UnsafePointer<UInt8>) in
                let rawBytes = UnsafeRawPointer(bytes)
                
                sent = withUnsafePointer(to: &serverAddress.sin) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        let sockLength = socklen_t(serverAddress.sin.sin_len)
                        return sendto(UDPSocket, rawBytes, data.count, 0, $0, sockLength)
                    }
                }
            }
            
        case AF_INET6:
            let serverAddress6 = SocketAddress6()
            guard serverAddress6.setFromString(host) else {
                print("Failed to convert \(host) into an IPv6 address")
                return
            }
            serverAddress6.setPort(port)
            
            data.withUnsafeBytes {
                (bytes: UnsafePointer<UInt8>) in
                let rawBytes = UnsafeRawPointer(bytes)
                
                sent = withUnsafePointer(to: &serverAddress6.sin6) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        let sockLength = socklen_t(serverAddress6.sin6.sin6_len)
                        return sendto(UDPSocket, rawBytes, data.count, 0, $0, sockLength)
                    }
                }
            }
            
        default:
            return
        }
        
        guard sent > 0 else {
            if let errorString = String(utf8String: strerror(errno)) {
                print("UDP connection failed to send data to host = \(host) port \(port). error = \(errorString)")
            }
            close(UDPSocket)
            return
        }
        
        if sent == data.count {
            // Success
            var connectionName = ""
            if let debugName = self.debugName {
                connectionName = debugName
            }
            print("UDP connection \(connectionName) sent \(data.count) bytes to host = \(host) port \(port)")
        }
    }
    
    /// Convert a sockaddr structure into an IP address string and port.
    func getEndpointInfo(socketAddressPointer: UnsafePointer<sockaddr>) -> (host: String, port: Int)?
    {
        let socketAddress = socketAddressPointer.pointee
        
        var result: (host: String, port: Int)?
        switch Int32(socketAddress.sa_family) {
        case AF_INET:
            socketAddressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                var socketAddressInet = $0.pointee
                let length = Int(INET_ADDRSTRLEN) + 2
                var buffer = [CChar](repeating: 0, count: length)
                let host = String(cString: inet_ntop(AF_INET, &socketAddressInet.sin_addr, &buffer, socklen_t(length)))
                let port = Int(UInt16(socketAddressInet.sin_port).byteSwapped)
                result = (host: host, port: port)
            }
            
        case AF_INET6:
            socketAddressPointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                var socketAddressInet6 = $0.pointee
                let length = Int(INET6_ADDRSTRLEN) + 2
                var buffer = [CChar](repeating: 0, count: length)
                let host = String(cString: inet_ntop(AF_INET6, &socketAddressInet6.sin6_addr, &buffer, socklen_t(length)))
                let port = Int(UInt16(socketAddressInet6.sin6_port).byteSwapped)
                result = (host: host, port: port)
            }
        default:
            result = nil
        }
        
        return result
    }
}
