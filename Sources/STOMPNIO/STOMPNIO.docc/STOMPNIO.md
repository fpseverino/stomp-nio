# ``STOMPNIO``

A Swift NIO based STOMP v1.0, v1.1 and v1.2 client.

## Overview

**Simple (or Streaming) Text Oriented Message Protocol** ([**STOMP**](https://stomp.github.io)) is a simple interoperable protocol designed for asynchronous message passing between clients via mediating servers.
It defines a text based wire-format for messages passed between these clients and servers.
STOMP has been in active use for several years and is supported by many message brokers and client libraries.

## Topics

### Connections

- ``STOMPConnection``
- ``STOMPServerAddress``
- ``STOMPConnectionConfiguration``
- ``STOMPClientError``

### Frames

- ``STOMPFrame``
- ``STOMPHeaders``
- ``STOMPHeader``

### Subscriptions

- ``STOMPSubscription``

### Transactions

- ``STOMPTransaction``