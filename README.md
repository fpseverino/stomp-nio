# STOMP NIO

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/fpseverino/stomp-nio/ci.yml)
![Codecov](https://img.shields.io/codecov/c/github/fpseverino/stomp-nio)

A Swift NIO based STOMP v1.0, v1.1 and v1.2 client.

> Heavily inspired by [Adam Fowler](https://github.com/adam-fowler)'s work on [MQTT NIO](https://github.com/swift-server-community/mqtt-nio) and [valkey-swift](https://github.com/valkey-io/valkey-swift).

**Simple (or Streaming) Text Oriented Message Protocol** (**STOMP**) is a simple interoperable protocol designed for asynchronous message passing between clients via mediating servers. It defines a text based wire-format for messages passed between these clients and servers.
STOMP has been in active use for several years and is supported by many message brokers and client libraries.