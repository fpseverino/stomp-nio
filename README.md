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
- POSIX sockets and Unix domain sockets
- Apple's Network framework via [NIOTransportServices](https://github.com/apple/swift-nio-transport-services) (required for iOS)
- [Swift Configuration](https://github.com/apple/swift-configuration) to create `STOMPClientConfiguration` and `STOMPConnectionConfiguration` from a configuration file
- [Task-local loggers](https://swiftpackageindex.com/apple/swift-log/documentation/logging/slg-0006-task-local-logger) from SwiftLog

## Overview

Create a client with server connection details:

```swift
import STOMPNIO

let stompClient = STOMPClient(.hostname("localhost"))
```

The `STOMPClient` uses a connection pool, which requires a background process to manage it.

You can run the background process using `async let`. When you leave the scope of the function your `async let` variable is declared the client will be shutdown.

```swift
let stompClient = STOMPClient(.hostname("localhost"))
async let _ = stompClient.run()

// Use STOMP client
try await stompClient.send("Hello, World!", to: "/queue/a")
// Client continues running in background
```

Alternatively you could also use a `TaskGroup`.

```swift
try await withThrowingTaskGroup { group in
    group.addTask {
        await stompClient.run()
    }

    // All operations happen in the closure body
    try await stompClient.send("Hello, World!", to: "/queue/a")

    // When done, cancel the run() task
    group.cancelAll()
}
// Client is shut down when task group exits
```

Or you can use `STOMPClient` with [`swift-service-lifecycle`](https://github.com/swift-server/swift-service-lifecycle) for long-running services.

```swift
let services: [Service] = [myApp, stompClient]
let serviceGroup = ServiceGroup(
    services: services,
    gracefulShutdownSignals: [.sigint, .sigterm],
    logger: Logger(...)
)
try await serviceGroup.run()
```

Once you have a STOMP client setup and running you can send STOMP frames directly from the `STOMPClient`.

```swift
try await stompClient.send("Hello, STOMP over NIO!", to: "/queue/a")
```

Or you can subscribe to destinations using `STOMPClient.subscribe`. A single connection is used for all subscriptions.

```swift
try await stompClient.subscribe(to: "/queue/a") { subscription in
    for try await frame in subscription {
        print(String(buffer: frame.body))
    }
}
```

## Documentation

User guides and reference documentation for STOMP NIO can be found on the [Swift Package Index](https://swiftpackageindex.com/fpseverino/stomp-nio/documentation).
