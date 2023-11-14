from .ThreadedHttpServer import ThreadedHttpServer
from http.server import SimpleHTTPRequestHandler
import json
# from typing import Callable
from typing import Dict, Any
import logging

logging.basicConfig()
logging.getLogger().setLevel(logging.INFO)


class Job:
    """A job to be executed by the JobServer."""

    def __init__(self, assigned_to: str, task: str) -> None:
        self.assigned_to = assigned_to
        self.task = task

    def to_json(self) -> Dict[str, Any]:
        """Convert the job to a JSON object."""
        return {'assigned_to': self.assigned_to, 'task': self.task}


class Worker:
    """A worker which can be assigned jobs"""

    def __init__(self, worker_id: str) -> None:
        self.worker_id = worker_id


class JobServerHandler(SimpleHTTPRequestHandler):
    """A handler for the JobServer. This is a subclass of SimpleHTTPRequestHandler that adds a job queue and a method for adding jobs to the queue."""

    def __init__(self, *args, job_queue: list[Job] = [], worker_registry: list[Worker] = [], **kwargs) -> None:
        """Initialise the handler with a job queue."""
        self.job_queue = job_queue
        self.worker_registry = worker_registry
        # Filter out any kwargs that are not accepted by the SimpleHTTPRequestHandler
        kwargs = {key: value for key, value in kwargs.items() if key in SimpleHTTPRequestHandler.__init__.__code__.co_varnames}
        super().__init__(*args, **kwargs)

    def add_job(self, job_str: str) -> None:
        """Add a job to the queue."""

        # if its a query string, parse it
        if "octave_query=" in job_str:
            body = dict(qc.split("=") for qc in job_str.split("&"))
            # remove the octave_query key
            body.pop("octave_query")
            job = Job(**body)
        else:  # otherwise, its a json string
            # convert the string to a Job object
            job = Job(**json.loads(job_str))

        self.job_queue.append(job)

    def add_worker(self, worker_str: str) -> None:
        """Add a worker to the queue."""

        # if its a query string, parse it
        if "octave_query=" in worker_str:
            body = dict(qc.split("=") for qc in worker_str.split("&"))
            # remove the octave_query key
            body.pop("octave_query")
            # remove anything not in the Worker constructor
            body = {key: value for key, value in body.items() if key in Worker.__init__.__code__.co_varnames}
            worker = Worker(**body)
        else:  # otherwise, its a json string
            # convert the string to a Job object
            worker = Worker(**json.loads(worker_str))

        # add the worker to the registry
        self.worker_registry.append(worker)

    def print_job_queue(self) -> None:
        """Print the job queue."""
        print(self.job_queue)

    def send_json_response(self, status_code: int, content: dict[str, Any]) -> None:
        """Send a JSON response with the given status code."""
        self.send_response(status_code)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(content).encode("utf-8"))

    def do_GET(self) -> None:
        """
        This handles the GET request. This includes:
        - /jobs: Return the job queue
        """
        logging.info(f"GET request,\nPath: {self.path}\nHeaders:\n{self.headers}\n")
        # check the path
        if "/jobs" in self.path:
            # get the query string
            query = {}
            if "?" in self.path:
                query_string = self.path.split("?")[1]
                # parse the query string
                query = dict(qc.split("=") for qc in query_string.split("&"))
            # get the assigned_to parameter
            assigned_to = query.get("assigned_to", None)
            # filter the job queue
            if assigned_to is not None:
                response = [job.to_json() for job in self.job_queue if job.assigned_to == assigned_to]
            else:
                response = [job.to_json() for job in self.job_queue]
            # return the job queue
            self.send_json_response(200, {"jobs": response})
        else:
            # call the parent method
            super().do_GET()

    def do_POST(self) -> None:
        """
        Handle post requests. This includes:
        - /add_job: Add a job to the queue
        """
        logging.info(f"POST request,\nPath: {self.path}\nHeaders:\n{self.headers}\n")
        # check the path
        if "/add_job" in self.path:
            # get the content length
            content_length = int(self.headers["Content-Length"])
            # get the body
            body = self.rfile.read(content_length)
            # decode the body
            body = body.decode("utf-8")
            # log the request
            logging.info(f"POST request,\nPath: {self.path}\nHeaders:\n{self.headers}\nBody:\n{body}\n")
            # add the job to the queue
            self.add_job(body)
            # send the json response
            self.send_json_response(200, {"message": "Job posted successfully"})
        if '/worker' in self.path:
            # get the content length
            content_length = int(self.headers["Content-Length"])
            assert content_length > 0, "Empty post request"
            # get the body
            body = self.rfile.read(content_length)
            # decode the body
            body = body.decode("utf-8")
            # log the request
            logging.info(f"POST request,\nPath: {self.path}\nHeaders:\n{self.headers}\nBody:\n{body}\n")
            # register the worker
            self.add_worker(body)
            # send the json response
            self.send_json_response(200, {"message": "Worker registered successfully"})
        else:
            # send a 404
            self.send_response(404)


class HttpJobServer(ThreadedHttpServer):
    def __init__(self, *args, **kwargs):
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
    import sys
    import src.openinsar_core.DeploymentConfig as DeploymentConfig

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
