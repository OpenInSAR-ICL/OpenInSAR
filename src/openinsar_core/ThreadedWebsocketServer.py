import threading
from websockets.sync.server import serve, ServerConnection
from time import time
from typing_extensions import Self  # Use typing_extensions, not typing, for early Python versions


class Message:
    """A message sent or received by the websocket server. Automatically records the timestamp on construction."""
    def __init__(self, message: str, timestamp: float = time()):
        self.timestamp = timestamp
        self.message = message

    def __repr__(self):
        """Format the message as a string with the timestamp."""
        return f"Message(message={self.message}, timestamp={self.timestamp})"

    def __str__(self):
        """Return the message as a string."""
        return self.message

    def __eq__(self, other: str | Self):
        """Check if the message is equal to another message, which can be a string or a Message object."""
        if isinstance(other, str):
            return self.message == other
        elif isinstance(other, Message):
            return self.message == other.message
        else:
            return False


class WebsocketMessageHandler:
    """Base class for websocket message handlers."""
    def __init__(self, max_history_length: int = 1000):
        self.message_received_history: list[Message] = []
        self.message_sent_history: list[Message] = []
        self.max_history_length = max_history_length

    def __call__(self, conn: ServerConnection) -> None:
        for message in conn:
            self.log_message_in(message)
            conn.send(message)
            self.log_message_out(message)

    def log_message_in(self, message: str | Message) -> None:
        """Log a message received by the server.
        If a string is provided, it will be converted to a Message object."""
        if isinstance(message, str):
            message = Message(message)
        if len(self.message_received_history) >= self.max_history_length:
            self.message_received_history.pop(0)
        self.message_received_history.append(message)

    def log_message_out(self, message: str | Message) -> None:
        """
        Log a message sent by the server.
        If a string is provided, it will be converted to a Message object.
        """
        if isinstance(message, str):
            message = Message(message)
        if len(self.message_sent_history) >= self.max_history_length:
            self.message_sent_history.pop(0)
        self.message_sent_history.append(message)


class EchoWebsocketHandler(WebsocketMessageHandler):
    """A specialized handler that echoes the received messages."""
    def __call__(self, conn: ServerConnection) -> None:
        """Echo the message back to the client."""
        for message in conn:
            conn.send(message)
        print("Echo handler finished")


class ThreadedWebsocketServer:
    """
    A Websocket server that runs in a thread and can be started and stopped at runtime.
    The server uses a WebsocketMessageHandler to determine what to do with messages, see :class:`WebsocketMessageHandler`.
    """
    def __init__(self, address: str = "localhost",
                 port: int = 8765,
                 handler: WebsocketMessageHandler = EchoWebsocketHandler()):
        self.address = address
        self.port = port
        self._thread = None
        self._server = None  # For shutdown we need a reference to the server object in the thread
        self.handler = handler

    def launch(self) -> None:
        """Launch the threaded server."""
        self._thread = threading.Thread(target=self.serve_forever, daemon=True)
        self._server = serve(self.handler, host=self.address, port=self.port)
        self._thread.start()

    def serve_forever(self) -> None:
        assert self._server is not None, "Server not initialised"
        self._server.serve_forever()

    def stop(self) -> None:
        """Stop the server."""
        if self._thread is not None:
            if self._server is not None:
                self._server.shutdown()
            self._thread.join()
            self._thread = None

    def get_received_messages(self) -> list[Message]:
        """Get the messages received by the server."""
        return self.handler.message_received_history

    def get_sent_messages(self) -> list[Message]:
        """Get the messages sent by the server."""
        return self.handler.message_sent_history


if __name__ == "__main__":
    """Example usage"""
    # Initialise the server
    ws_server = ThreadedWebsocketServer(port=8765)
    # Start the server
    ws_server.launch()
    # Do something else, in this case wait for a KeyboardInterrupt
    while True:
        try:
            time.sleep(1)
        except KeyboardInterrupt:
            break
    # Stop the server
    ws_server.stop()
