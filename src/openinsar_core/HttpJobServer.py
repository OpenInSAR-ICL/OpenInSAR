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

    def __repr__(self) -> str:
        return f"Job(assigned_to={self.assigned_to}, task={self.task})"

    def __str__(self) -> str:
        return f"Job assigned to {self.assigned_to}: {self.task}"

    def to_json(self) -> Dict[str, str]:
        return {'assigned_to': self.assigned_to, 'task': self.task}


class JobServerHandler(SimpleHTTPRequestHandler):
    """A handler for the JobServer. This is a subclass of SimpleHTTPRequestHandler that adds a job queue and a method for adding jobs to the queue."""

    def __init__(self, *args, job_queue: list[Job] = [], **kwargs) -> None:
        """Initialise the handler with a job queue."""
        self.job_queue = job_queue
        # Filter out any kwargs that are not accepted by the SimpleHTTPRequestHandler
        kwargs = {key: value for key, value in kwargs.items() if key in SimpleHTTPRequestHandler.__init__.__code__.co_varnames}
        super().__init__(*args, **kwargs)

    def add_job(self, job_str: str) -> None:
        """Add a job to the queue."""
        # convert the string to a Job object
        job = Job(**json.loads(job_str))
        self.job_queue.append(job)

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
        else:
            # send a 404
            self.send_response(404)


class HttpJobServer(ThreadedHttpServer):
    def __init__(self, *args, **kwargs):
        # filter out any kwargs that are not accepted by the ThreadedHttpServer
        kwargs = {key: value for key, value in kwargs.items() if key in ThreadedHttpServer.__init__.__code__.co_varnames}
        super().__init__(*args, handler=JobServerHandler, **kwargs)


def main():
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
    else:
        raise ValueError(f"Unknown platform: {platform}")

    # Initialise the server
    html_server = HttpJobServer(config=config)
    # Start the server
    html_server.launch()


if __name__ == "__main__":
    main()
