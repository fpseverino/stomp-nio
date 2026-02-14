# STOMP NIO

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffpseverino%2Fstomp-nio%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/fpseverino/stomp-nio)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffpseverino%2Fstomp-nio%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/fpseverino/stomp-nio)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/fpseverino/stomp-nio/ci.yml)
![Codecov](https://img.shields.io/codecov/c/github/fpseverino/stomp-nio)

A Swift NIO based STOMP v1.0, v1.1 and v1.2 client.

> Heavily inspired by [Adam Fowler](https://github.com/adam-fowler)'s work on [MQTT NIO](https://github.com/swift-server-community/mqtt-nio) and [valkey-swift](https://github.com/valkey-io/valkey-swift).

**Simple (or Streaming) Text Oriented Message Protocol** ([**STOMP**](https://stomp.github.io)) is a simple interoperable protocol designed for asynchronous message passing between clients via mediating servers.
It defines a text based wire-format for messages passed between these clients and servers.
STOMP has been in active use for several years and is supported by many message brokers and client libraries.

STOMPNIO is a Swift NIO based implementation of a STOMP client. It supports:
- STOMP versions 1.0, 1.1, and 1.2
- Unencrypted and encrypted (via TLS) connections
- WebSocket connections
- POSIX sockets
- Apple's Network framework via [NIOTransportServices](https://github.com/apple/swift-nio-transport-services) (required for iOS)
- Unix domain sockets

## Overview

The STOMP NIO project uses a connection pool, which requires a background process to manage it.
You can either run it using a `TaskGroup` or `async let`.
Below we are using `async let` to run the connection pool background process.

```swift
let stompClient = STOMPClient(.hostname("localhost"), logger: logger)
async let _ = stompClient.run()
// use STOMP client
```

Or you can use `STOMPClient` with [`swift-service-lifecycle`](https://github.com/swift-server/swift-service-lifecycle).

Once you have a STOMP client setup and running you can send STOMP frames directly from the `STOMPClient`.

```swift
try await stompClient.send("Hello, STOMP over NIO!", to: "/queue/a")
```

Or you can create a connection and subscribe to destinations from that connection using `STOMPClient.withConnection()`.

```swift
try await stompClient.withConnection { connection in
    try await connection.subscribe(to: "/queue/a") { subscription in
        for try await frame in subscription {
            print(String(buffer: frame.body))
        }
    }
}
```

## Documentation

User guides and reference documentation for STOMP NIO can be found on the [Swift Package Index](https://swiftpackageindex.com/fpseverino/stomp-nio/documentation).
