import pytest
from src.openinsar_core.ThreadedWebsocketServer import ThreadedWebsocketServer
from test.TestUtilities import lock_resource
from websockets.sync.client import connect

assert lock_resource is not None  # Just to shut up the linters who think its unused


def client_send_recieve(message_to_send: str, port: int, address: str = "localhost", is_wss: bool = False) -> str:
    """Create a client, send a message, receive a message, close the client, return the message."""
    # Create a websocket client
    protocol = "wss" if is_wss else "ws"
    server_uri = f"{protocol}://{address}:{port}"
    conn = connect(server_uri)
    assert conn is not None, "Failed to connect to websocket server"
    # Send a message
    conn.send(message_to_send)
    # Receive a message
    try:
        result = conn.recv(1)
    except TimeoutError:
        result = None
    # Close the client
    conn.close()
    return result


def client_send_multiple_messages(messages: list[str], port: int, address: str = "localhost", is_wss: bool = False) -> str:
    """Create a client, send a message, receive a message, close the client, return the message."""
    # Create a websocket client
    protocol = "wss" if is_wss else "ws"
    server_uri = f"{protocol}://{address}:{port}"
    conn = connect(server_uri)
    # Send messages
    for message in messages:
        conn.send(message)
    # Receive any messages
    result = []
    try:
        while True:
            result.append(conn.recv(1))
    except TimeoutError:
        pass
    # Close the client
    conn.close()
    return result


@pytest.mark.parametrize("lock_resource", ["port8765"], indirect=True, ids=["Use port 8765"])  # Mutex for the port
def test_websocket_server(lock_resource):
    """Test setting up the websocket server and receiving a message"""
    ws_server = ThreadedWebsocketServer(port=8765)
    ws_server.launch()
    # Send a message
    result = client_send_recieve("Hello, World!", 8765)
    assert result == "Hello, World!"
    # Stop the server
    ws_server.stop()


@pytest.mark.parametrize("lock_resource", ["port8766"], indirect=True, ids=["Use port 8766"])  # Mutex for the port
def test_websocket_echo(lock_resource):
    """Test echoing a message back from the server"""
    ws_server = ThreadedWebsocketServer(port=8766)
    ws_server.launch()
    # Send a message
    result = client_send_recieve("Hello, World!", 8766)
    assert result == "Hello, World!"
    # Stop the server
    ws_server.stop()


@pytest.mark.parametrize("lock_resource", ["port8767"], indirect=True, ids=["Use port 8767"])  # Mutex for the port
def test_message_handler_logs_received_messages(lock_resource):
    from src.openinsar_core.ThreadedWebsocketServer import WebsocketMessageHandler

    handler = WebsocketMessageHandler(max_history_length=2)
    ws_server = ThreadedWebsocketServer(port=8767, handler=handler)
    ws_server.launch()
    # Send three messages
    client_send_multiple_messages(["message1", "message2", "message3"], 8767)
    messages = ws_server.get_received_messages()
    assert len(messages) == 2
    assert "message2" in messages, "Message was not found in the list of received messages"
    assert "message3" in messages, "Message was not found in the list of received messages"
    assert "message1" not in messages, "The oldest message should have been removed"
