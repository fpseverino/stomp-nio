# Transactions

Perform atomic sending and acknowledging operations using STOMP transactions.

## Overview

Transactions in STOMP apply to sending and acknowledging - any messages sent or acknowledged during a transaction will be processed atomically based on the transaction.
To start a transaction in STOMP, you send a `BEGIN` frame to the broker with a `transaction` header containing a unique transaction ID.
Once a transaction is started, you can send or acknowledge messages as part of the transaction by including the same `transaction` header in the `SEND`, `ACK` or `NACK` frames.
To complete the transaction, you send a `COMMIT` frame with the same `transaction` header.
If you want to roll back the transaction instead, you send an `ABORT` frame with the same `transaction` header.
Any started transactions which have not been committed will be implicitly aborted if the client sends a `DISCONNECT` frame or if the TCP connection fails for any reason.

STOMP NIO provides support for executing transactions with an easy high-level API.

### Starting a Transaction

To start a transaction, use the ``STOMPConnection/withTransaction(_:)`` method.
This method takes a closure that receives a ``STOMPTransaction`` instance representing the transaction.
You can use this instance to send messages as part of the transaction or to create subscriptions whose automatic acknowledgments will be part of the transaction.
When the closure returns successfully, the transaction is committed automatically.
If the closure throws an error, the transaction will be aborted.

```swift
try await STOMPConnection.withConnection(address: .hostname("localhost")) { connection in
    try await connection.withTransaction { transaction in
        try await transaction.send("Message in Transaction", to: "/queue/a")
    }
}
```

```swift
try await stompClient.withConnection { connection in
    try await connection.withTransaction { transaction in
        try await transaction.subscribe(to: "/queue/a") { subscription in
            for try await frame in subscription {
                print(String(buffer: frame.body))
            }
        }
    }
}
```

Even inside the transaction closure, you can send messages or create subscriptions that are not part of the transaction by using the original ``STOMPConnection`` instance.

```swift
try await STOMPConnection.withConnection(address: .hostname("localhost")) { connection in
    try await connection.withTransaction { transaction in
        try await withThrowingTaskGroup { group in
            group.addTask {
                try await transaction.subscribe(to: "/queue/a") { subscription in
                    for try await frame in subscription {
                        print(String(buffer: frame.body))
                    }
                }
            }

            group.addTask {
                try await connection.send("Message outside Transaction", to: "/queue/a")
            }
        }
    }
}
```

### Committing and Aborting

The transaction is committed automatically when the closure passed to ``STOMPConnection/withTransaction(_:)`` returns successfully.
If you want to abort the transaction instead, you can throw an error from the closure.

```swift
struct AbortTransaction: Error {}

try await stompClient.withConnection { connection in
    try await connection.withTransaction { transaction in
        try await transaction.send("Message in Transaction", to: "/queue/a")
        throw AbortTransaction()
    }
}
```

In this example, the message sent as part of the transaction will not be delivered to the destination, since the transaction is aborted.
