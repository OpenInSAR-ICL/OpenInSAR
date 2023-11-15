import json
from typing import Any
from http.server import SimpleHTTPRequestHandler


class Job:
    """A job to be executed by the JobServer."""

    def __init__(self, assigned_to: str, task: str) -> None:
        self.assigned_to = assigned_to
        self.task = task

    def to_json(self) -> dict[str, str]:
        """Convert the job to a JSON object."""
        return {'assigned_to': self.assigned_to, 'task': self.task}


class Worker:
    """A worker which can be assigned jobs"""

    def __init__(self, worker_id: str) -> None:
        self.worker_id = worker_id


class BaseJobServerHandler(SimpleHTTPRequestHandler):
    pass


def get_content(self) -> tuple[str, int]:
    # get the content length
    content_length = int(self.headers.get("Content-Length", 0))
    # if POST or PUT, there should be content
    request_type = self.command
    if content_length == 0:
        assert request_type == "GET", "No content provided"
        return ("", 0)
    # get the body
    body = self.rfile.read(content_length)
    # decode the body
    body = body.decode("utf-8")
    return (body, content_length)


def send_json_response(self, status_code: int, content: dict[str, Any]) -> None:
    """Send a JSON response with the given status code."""
    self.send_response(status_code)
    self.send_header("Content-type", "application/json")
    self.end_headers()
    self.wfile.write(json.dumps(content).encode("utf-8"))


def handle_get_jobs(handler, worker_id: str) -> None:
    # get the query string
    query = {}
    if "?" in handler.path:
        query_string = handler.path.split("?")[1]
        # parse the query string
        query = dict(qc.split("=") for qc in query_string.split("&"))
    # get the assigned_to parameter
    assigned_to = query.get("assigned_to", None)
    # filter the job queue
    if assigned_to is not None:
        response = [job.to_json() for job in handler.job_queue if job.assigned_to == assigned_to]
    else:
        response = [job.to_json() for job in handler.job_queue]
    # return the job queue
    send_json_response(handler, 200, {"jobs": response})


def handle_add_job(handler, job_str: str) -> None:
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

    handler.job_queue.append(job)
    send_json_response(handler, 200, {"success": True})


def handle_add_worker(handler, worker_str: str) -> None:
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
    handler.worker_registry.append(worker)
    send_json_response(handler, 200, {"success": True})
