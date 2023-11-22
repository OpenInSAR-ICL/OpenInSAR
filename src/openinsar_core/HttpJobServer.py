import json
from .ThreadedHttpServer import ThreadedHttpServer
from .MessageHandling import Job, Worker, BaseJobServerHandler
from .Messages import messages
from typing import Any


class JobServerHandler(BaseJobServerHandler):
    """A handler for the JobServer. This is a subclass of SimpleHTTPRequestHandler that adds a job queue and a method for adding jobs to the queue."""

    def __init__(self, *args, job_queue: list[Job] = [], worker_registry: list[Worker] = [], **kwargs) -> None:
        """Initialise the handler with a job queue."""
        self.job_queues: dict[Any, Any] = {}
        self.worker_registry: list[Any] = worker_registry

        # Filter out any kwargs that are not accepted by the SimpleHTTPRequestHandler
        kwargs: dict[str, Any]: = {key: value for key, value in kwargs.items() if key in BaseJobServerHandler.__init__.__code__.co_varnames}
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

    def success_response(self) -> None:
        self.send_response(200, "OK")
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(obj={"success": True}).encode(encoding="utf-8"))

    def handle_message(self, method) -> None:
        """Handle a message based on the path."""
        path_no_query = self.path.split("?")[0]
        if any([path_no_query is None, path_no_query == '', path_no_query == '/']):  # if the path is empty, return the index page
            path_no_query = '/index.html'
        else:
            path_no_query = path_no_query[1:]  # remove the leading slash

        message = messages.get(path_no_query)

        if message is None:
            if method == 'GET':
                # use the super do_get method
                super().do_GET()
            else:
                self.failure_response()
            return

        # Update default response callbacks
        failure_response = message.get(
            'failure_response',
            lambda self: self.failure_response())
        # decoder should return the content and the content length
        decoder = message.get(
            'decoder',
            lambda x: (None, 0))
        action = message.get(
            'action',
            lambda x: None)

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
        kwargs: dict[str, Any] = {key: value for key, value in kwargs.items() if key in ThreadedHttpServer.__init__.__code__.co_varnames}
        super().__init__(*args, handler=JobServerHandler, **kwargs)


def main() -> HttpJobServer:
    """
    Example usage. Runs the server on the specified platform:
    - render: Run the server on render.com
        >  python -m src.openinsar_core.HttpJobServer render
    - local: Run the server locally
        >  python -m src.openinsar_core.HttpJobServer local
    """
    import sys
    from . import DeploymentConfig

    # Get target platform from command line arguments
    if len(sys.argv) > 1:
        platform = sys.argv[1]
    else:
        platform = "local"

    # Switch the config based on the platform
    if platform == "render":
        config = DeploymentConfig.for_render()
    elif platform == "local":
        config = DeploymentConfig.for_local()
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
    # Start the server
    html_server.launch()

    return html_server  # to keep the server alive if we're running in a thread


if __name__ == "__main__":
    main()
