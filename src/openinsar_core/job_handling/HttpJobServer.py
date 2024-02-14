import sys
import json
from ..server.ThreadedHttpServer import ThreadedHttpServer
from ..server.SinglePageAppServer import SinglePageApplicationHandler
from ..server.DeploymentConfig import DeploymentConfig, for_local as get_local_config, for_render as get_render_config
from .EndpointHandlers import Job, Worker, BaseJobServerHandler
from .Endpoints import endpoints


class JobServerHandler(SinglePageApplicationHandler):
    """A handler for the JobServer. This is a subclass of SimpleHTTPRequestHandler that adds a job queue and a method for adding jobs to the queue."""
    job_queues: dict[str, list[Job]] = {}
    worker_pools: dict[str, list[Worker]] = {}
    user_sessions: dict[str, str] = {}

    def __init__(self, *args, job_queue: list[Job] = [], worker_registry: list[Worker] = [], **kwargs) -> None:
        """Initialise the handler with a job queue."""
        self.current_user: str | None = None
        # Filter out any kwargs that are not accepted by the SimpleHTTPRequestHandler
        kwargs = {key: value for key, value in kwargs.items() if key in BaseJobServerHandler.__init__.__code__.co_varnames}
        super().__init__(*args, **kwargs)

    def do_GET(self) -> None:
        """
        This handles the GET request. This includes:
        - /jobs: Return the job queue
        """
        self.handle_message(method='GET')

    def do_POST(self) -> None:
        """
        Handle post requests. This includes:
        - /add_job: Add a job to the queue
        """
        self.handle_message(method='POST')

    def log_request(self, code: int | str = "-", size: int | str = "-") -> None:
        """Override to prevent stderr logging."""
        print(f"{self.address_string()} - - [{self.log_date_time_string()}] {self.requestline} {code} {size}")

    def failure_response(self) -> None:
        self.send_response(500, "Not found")

    def failure_unauthorized(self) -> None:
        self.send_response(401, "Unauthorized")

    def success_response(self) -> None:
        self.send_response(200, "OK")
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(obj={"success": True}).encode(encoding="utf-8"))

    def handle_message(self, method) -> None:
        """Handle a message based on the path."""
        print(self.path)
        print(self.directory)
        split_path: list[str] = self.path.split("?")
        if len(split_path) > 1:
            path_no_query: str = split_path[0]
            self.query_string: str | None = split_path[1]
        else:
            path_no_query = split_path[0]
            self.query_string = None

        if path_no_query.startswith('/doc/'):
            self.directory = self.directory.replace('/app/', '/doc/')
            super().do_GET()
        elif path_no_query.startswith('/api/'):
            pass
        elif path_no_query.startswith('/') or path_no_query == '':
            self.directory = self.directory.replace('./output', './output/app')
            super().do_GET()
            return

        endpoint = endpoints.get(path_no_query)

        if endpoint is None:
            if method == 'GET':
                # use the super do_get method
                super().do_GET()
            else:
                self.failure_response()
            return

        if 'auth_required' in endpoint[method].keys() and endpoint[method]['auth_required']:
            # Get the token from the headers
            self.current_token: str | None = self.headers.get("Authorization", None)
            # ignore 'Bearer ' prefix
            if self.current_token is not None and self.current_token.startswith('Bearer '):
                self.current_token = self.current_token[7:]
            # Get the user from the token
            if self.current_token is not None:
                user: str | None = self.user_sessions.get(self.current_token, None)
                if user is not None:
                    self.current_user = user

            if self.current_user is None:
                # redirect to login
                try:
                    self.send_response(302, "Redirect")
                    self.send_header("Location", "/api/login")
                    self.end_headers()
                except ConnectionResetError:
                    self.failure_unauthorized()
                # self.failure_unauthorized()
                return

        # Update default response callbacks
        failure_response = endpoint[method].get(
            'failure_response',
            lambda self: self.failure_response())
        # decoder should return the content and the content length
        decoder = endpoint[method].get(
            'decoder',
            lambda x: (None, 0))
        action = endpoint[method].get(
            'action',
            lambda x: (None, 0))

        try:
            # get the content
            content, content_length = decoder(self)
            # do the action
            action(self, content)
        except Exception as e:
            print(e)
            failure_response(self)


class HttpJobServer(ThreadedHttpServer):
    def __init__(self, *args, **kwargs) -> None:
        self.handler: JobServerHandler
        # filter out any kwargs that are not accepted by the ThreadedHttpServer
        kwargs = {key: value for key, value in kwargs.items() if key in ThreadedHttpServer.__init__.__code__.co_varnames}
        super().__init__(*args, handler=JobServerHandler, **kwargs)


def main() -> HttpJobServer:
    """
    Example usage. Runs the server on the specified platform:
    - render: Run the server on render.com
        >  python -m src.openinsar_core.HttpJobServer render
    - local: Run the server locally
        >  python -m src.openinsar_core.HttpJobServer local
    """

    # Get target platform from command line arguments
    if len(sys.argv) > 1:
        platform = sys.argv[1]
    else:
        platform = "local"

    # Switch the config based on the platform
    config: DeploymentConfig = DeploymentConfig()
    if platform == "render":
        config = get_render_config()
    elif platform == "local":
        config = get_local_config()
        config.use_threading = False
    else:
        raise ValueError(f"Unknown platform: {platform}")

    # Override any config options with command line arguments
    if len(sys.argv) > 2:
        for arg in sys.argv[2:]:
            key, value = arg.split("=")
            if hasattr(config, key):
                # map the value to the correct type
                if type(getattr(config, key)) == bool:
                    value = value.lower() == "true"
                elif type(getattr(config, key)) == int:
                    value = int(value)
                elif type(getattr(config, key)) == float:
                    value = float(value)
                assert isinstance(getattr(config, key), type(value)), f"Type mismatch for {key}: {type(getattr(config, key))} != {type(value)}"
                setattr(config, key, value)
            else:
                raise ValueError(f"Unknown config option: {key}")

    # Initialise the server
    html_server = HttpJobServer(config=config)
    html_server.directory = './output'
    # Start the server
    html_server.launch()

    return html_server  # to keep the server alive if we're running in a thread


if __name__ == "__main__":
    # Set environment variables for username and password
    import os
    import bcrypt
    test_pass = 'test_password'
    # Hash the password
    hashed_pass: str = bcrypt.hashpw(test_pass.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    os.environ['USERS'] = "test_user:" + str(hashed_pass)
    main()
