# ``STOMPNIO``

A Swift NIO based STOMP v1.0, v1.1 and v1.2 client.

## Overview

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

## Topics

### Client

- <doc:GettingStarted>
- ``STOMPClient``
- ``STOMPClientConfiguration``
- ``STOMPServerAddress``
- ``STOMPClientError``

### Connections

- ``STOMPConnection``
- ``STOMPConnectionConfiguration``

### Frames

- ``STOMPFrame``
- ``STOMPHeaders``
- ``STOMPHeader``

### Subscriptions

- ``STOMPSubscription``

### Transactions

- <doc:Transactions-article>
- ``STOMPTransaction``

### TLS Encryption on Apple Platforms

- ``TSTLSConfiguration``
- ``TSTLSVersion``
- ``TSCertificateVerification``