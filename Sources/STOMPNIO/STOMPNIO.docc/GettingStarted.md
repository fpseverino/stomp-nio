# Getting Started using STOMPNIO

Add STOMP NIO to your project, manage the connections, and send frames.

## Overview

### Adding STOMPNIO as a dependency

Add STOMP NIO as a dependency to your project and targets that use it.

You can use the `add-dependency` command:

```bash
swift package add-dependency https://github.com/fpseverino/stomp-nio --from: 0.0.9
```

or edit Package.swift directly:
```swift
dependencies: [
    .package(url: "https://github.com/fpseverino/stomp-nio.git", from: "0.0.9"),
]
```

And for the relevant target or targets.
The following example shows how to add to STOMP NIO as a dependency to the target `MyApp`:

```bash
swift package add-target-dependency STOMPNIO MyApp --package stomp-nio
```

You can also edit the dependencies for that target directly in Package.swift:
```swift
dependencies: [
    .product(name: "STOMPNIO", package: "stomp-nio"),
]
```

> Note: If you are building an executable for macOS, STOMP NIO has a minimum platform dependency you need to accomodate.
> For example, you may want to add a minimum platform requirement to your project:
>
> ```swift
> platforms: [.macOS(.v15)],
> ```

Import STOMP NIO in the swift files to use it:

```swift
import STOMPNIO
```

### Enabling connections to a STOMP server

``STOMPClient`` uses a connection pool that requires a background root task to run all the maintenance work required to establish connections.
You can either run them using a Task group, for example:

```swift
let stompClient = STOMPClient(.hostname("localhost"))
try await withThrowingTaskGroup { group in
    group.addTask {
        // run connection pool in the background
        await stompClient.run()
    }
    // use STOMP client
}
```

Or you can use [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle) to manage the connection manager.

```swift
let stompClient = STOMPClient(.hostname("localhost"))

let services: [Service] = [stompClient, webServer, otherService]
let serviceGroup = ServiceGroup(
    services: services,
    gracefulShutdownSignals: [.sigint],
    cancellationSignals: [.sigterm],
    logger: Logger(...)
)
try await serviceGroup.run()
```

### Sending and receiving frames

Once you have your connection pool up and running the client is ready to use, you can send and receive frames.
`STOMPClient` uses a connection from the connection pool for each call:

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

### Logging

By default, ``STOMPClient/init(_:configuration:eventLoopGroup:logger:)`` and ``STOMPConnection/withConnection(address:configuration:eventLoop:logger:operation:)`` use the current task-local logger ([`Logger.current`](https://swiftpackageindex.com/apple/swift-log/documentation/logging/logger/current)), which by default is a `Logger` with an empty label and a log level of `.info`.

You can set a custom logger for the connection by passing it via a parameter to `STOMPClient` initializer or the `withConnection` method, or you can wrap the client/connection creation code within a `withLogger` closure, which will set a task-local logger.

```swift
// Your custom logger
var myLogger = Logger(label: "com.example.stomp")
myLogger.logLevel = .trace

// Pass the logger to the `STOMPClient` initializer
let stompClient = STOMPClient(.hostname("localhost"), logger: myLogger)
async let _ = stompClient.run()
// Client events will be logged with `myLogger`

// Pass the logger to the `withConnection` method
try await STOMPConnection.withConnection(
    address: .hostname("localhost"),
    logger: myLogger
) { connection in
    // Connection events will be logged with `myLogger`
}

// OR:

// Wrap the client creation code within a `withLogger` closure
try await withLogger(myLogger) { _ in
    let stompClient = STOMPClient(.hostname("localhost"))
    async let _ = stompClient.run()
    // Client events will be logged with `myLogger`
}

// Wrap the connection creation code within a `withLogger` closure
try await withLogger(myLogger) { _ in
    try await STOMPConnection.withConnection(address: .hostname("localhost")) { connection in
        // Connection events will be logged with `myLogger`
    }
}
```
