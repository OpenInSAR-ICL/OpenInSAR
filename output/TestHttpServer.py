import socket
import http.server
import os
import json
# import threading


def find_available_port():
    # Create a socket object
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    # Bind to an available port
    sock.bind(('localhost', 0))  # Using 'localhost' and port 0 to allow the system to allocate an available port

    # Get the assigned port
    _, port = sock.getsockname()

    # Close the socket
    sock.close()

    return port


def get_server_ip():
    # Create a temporary socket to get the local IP address
    temp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    temp_sock.connect(('8.8.8.8', 80))  # Connecting to a known IP address (Google's DNS server)
    ip_address = temp_sock.getsockname()[0]
    temp_sock.close()

    return ip_address


class MessageQueueHandler(http.server.BaseHTTPRequestHandler):
    message_queue = []

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def do_GET(self) -> None:
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

        print("Sending message queue to client")
        print(self.message_queue)

        # dump the message queue into a json string
        msg_queue_json = json.dumps(self.message_queue).encode()
        self.wfile.write(msg_queue_json)

    def do_POST(self) -> None:
        # get the content length
        content_length = int(self.headers['Content-Length'])
        # read the content
        post_data = self.rfile.read(content_length)

        # parse the content
        post_data = json.loads(post_data)
        # add the message to the message queue
        self.message_queue.append(post_data)
        # send a response
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'message': 'Message received'}).encode())

        # print the msg queue to terminal
        print(self.message_queue)

        # print the sender_id
        sid = post_data['sender_id']
        print(f"Sender ID: {sid}")

    def log_message(self, format, *args):
        """Suppress the default logging which prints to stderr"""
        return


def run_http_server(port):
    # Create an HTTP server
    server_address = ('', port)
    httpd = http.server.HTTPServer(server_address, MessageQueueHandler)

    # Start the HTTP server
    print(f"Starting HTTP server on port {port}")
    httpd.serve_forever()


if __name__ == "__main__":
    available_port = find_available_port()

    # Get home directory
    home_dir = os.path.expanduser("~")
    info_file_path = os.path.join(home_dir, "server_info.txt")
    print(f"Server info file path: {info_file_path}")

    # Write IP address and port to a file
    with open(info_file_path, "w") as file:
        ip_address = get_server_ip()
        file.write(f"Server IP: {ip_address}\n")
        file.write(f"Server Port: {available_port}\n")

    # Run HTTP server on the available port
    # thread = threading.Thread(target=run_http_server, args=(available_port,))
    # Run the HTTP server in the main thread
    run_http_server(available_port)
