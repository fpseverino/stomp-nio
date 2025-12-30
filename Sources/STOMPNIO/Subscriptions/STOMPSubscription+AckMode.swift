extension STOMPSubscription {
    /// STOMP acknowledgment modes for subscriptions
    public enum AckMode: String, Sendable, CaseIterable {
        /// The client does not need to send the server ACK frames for the messages it receives.
        ///
        /// The server will assume the client has received the message as soon as it sends it to the client.
        ///
        /// This acknowledgment mode can cause messages being transmitted to the client to get dropped.
        case auto = "auto"
        /// The client MUST send the server ACK frames for the messages it processes.
        ///
        /// If the connection fails before a client sends an ACK frame for the message
        /// the server will assume the message has not been processed and MAY redeliver the message to another client.
        ///
        /// The ACK frames sent by the client will be treated as a cumulative acknowledgment.
        /// This means the acknowledgment operates on the message specified in the ACK frame
        /// and all messages sent to the subscription before the ACK'ed message.
        ///
        /// In case the client did not process some messages,
        /// it SHOULD send NACK frames to tell the server it did not consume these messages.
        case client = "client"
        /// The acknowledgment operates just like the client acknowledgment mode
        /// except that the ACK or NACK frames sent by the client are not cumulative.
        ///
        /// This means that an ACK or NACK frame for a subsequent message MUST NOT cause a previous message to get acknowledged.
        case clientIndividual = "client-individual"
    }
}
