from http.server import HTTPServer, BaseHTTPRequestHandler, SimpleHTTPRequestHandler
from socketserver import ThreadingMixIn
from src.openinsar_core.job_handling.HttpJobServer import JobServerHandler, Job, Worker, HttpJobServer
from src.openinsar_core.server.DeploymentConfig import DeploymentConfig, for_render as get_render_config, for_local as get_local_config
import threading
from time import sleep
import os
import sys

class MainHandler(JobServerHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def do_GET(self):
        print(self.path)
        if self.path.startswith('/api/'):
            super().do_GET()
        else:
            SimpleHTTPRequestHandler.do_GET(self)

    def do_POST(self):
        print(self.path)
        if self.path.startswith('/api/'):
            super().do_POST()
        else:
            # send 404
            self.send_response(404)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b"Page not found")

# Create a threaded HTTP server

def main() -> HttpJobServer:
    """
    Example usage. Runs the server on the specified platform:
    - render: Run the server on render.com
        >  python -m src.openinsar_core.HttpJobServer render
    - local: Run the server locally
        >  python -m src.openinsar_core.HttpJobServer local
    """


    config = get_local_config()
    # Initialise the server
    html_server = HttpJobServer(config=config)
    print(1)
    html_server.handler = MainHandler
    html_server.use_threading = True
    print(2)
    html_server.directory = './output/app'
    # Start the server
    html_server.launch()
    print(3)

    return html_server  # to keep the server alive if we're running in a thread


if __name__ == "__main__":
    # Set environment variables for username and password
    import os
    import bcrypt
    test_pass = 'test_password'
    # Hash the password
    hashed_pass: str = bcrypt.hashpw(test_pass.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    os.environ['USERS'] = "test_user:" + str(hashed_pass)
    t = main()
    try:
        while True:
            sleep(1)
    except KeyboardInterrupt:
        t.stop()
        print('Stopped')
        sys.exit(0)
