from __future__ import annotations
import json
import os
import secrets
from typing import Any, TYPE_CHECKING, Iterator
from http.server import SimpleHTTPRequestHandler
import bcrypt


class Job:
    """A job to be executed by the JobServer."""

    def __init__(self, assigned_to: str, task: str) -> None:
        self.assigned_to = assigned_to
        self.task = task

    def to_json(self) -> dict[str, str]:
        """Convert the job to a JSON object."""
        return {'assigned_to': self.assigned_to, 'task': self.task}

    def __repr__(self) -> str:
        return f"Job(assigned_to={self.assigned_to}, task={self.task})"


class Queue:
    """A named queue of jobs."""

    def __init__(self, queue_id: str) -> None:
        self.queue_id: str = queue_id
        self.jobs: list[Job] = []

    def to_json(self) -> dict[str, Any]:
        """Convert the queue to a JSON object."""
        return {'queue_id': self.queue_id, 'jobs': [job.to_json() for job in self.jobs]}

    def __repr__(self) -> str:
        return f"Queue(queue_id={self.queue_id}, jobs={self.jobs})"

    def __iter__(self) -> Iterator[Job]:
        """Iterate over the jobs in the queue."""
        return iter(self.jobs)

    def __len__(self) -> int:
        """Get the number of jobs in the queue."""
        return len(self.jobs)

    def __getitem__(self, index: int) -> Job:
        """Get the job at the given index."""
        return self.jobs[index]

    def append(self, job: Job) -> None:
        """Add a job to the queue."""
        self.jobs.append(job)


class Worker:
    """A worker which can be assigned jobs"""

    def __init__(self, worker_id: str) -> None:
        self.worker_id = worker_id

    def to_json(self) -> dict[str, str]:
        """Convert the worker to a JSON object."""
        return {'worker_id': self.worker_id}


if TYPE_CHECKING:
    class JobServerHandler(SimpleHTTPRequestHandler):
        job_queues: dict[str, Queue]
        worker_pools: dict[str, list[Worker]]
        user_sessions: dict[str, str]
        current_user: str | None


class BaseJobServerHandler(SimpleHTTPRequestHandler):
    pass


def handle_get_login(handler: JobServerHandler, body: str) -> None:
    """Create a basic form for submitting a login request."""
    handler.send_response(200)
    handler.send_header("Content-type", "text/html")
    handler.end_headers()
    handler.wfile.write(b"""
    <html>
        <head>
            <title>Login</title>
        </head>
        <body>
            <form action="/api/login" method="POST">
                <input type="text" name="username" placeholder="Username" />
                <input type="password" name="password" placeholder="Password" />
                <input type="submit" value="Login" />
            </form>
        </body>
    </html>
    """)
    return


def handle_login(handler: JobServerHandler, body: str) -> None:
    """Handle a login request."""
    # Get the username and password from the body
    # This might be a query string or a json string
    if "username=" in body:
        body_dict = dict(qc.split("=") for qc in body.split("&"))
    else:
        body_dict: dict[str, Any] = json.loads(body)
    assert "username" in body_dict, "Username not provided"
    assert "password" in body_dict, "Password not provided"
    username: str = body_dict["username"]
    password: str = body_dict["password"]

    # Get the users from the environment variable
    users_envvar: str | None = os.getenv('USERS')
    assert users_envvar is not None, "USERS environment variable not set"
    users: list[str] = users_envvar.split(',')

    # Check if the user exists
    for user in users:
        user_name, user_hashed_password = user.split(':')
        if user_name == username:
            if bcrypt.checkpw(password.encode(), user_hashed_password.encode()):
                # Generate a session token
                token = secrets.token_hex(16)
                # Store the token and username in some storage
                # For simplicity, we'll use a global dictionary
                handler.user_sessions[token] = username
                # Create entry in job_queues and worker_pools if they don't exist
                if username not in handler.job_queues:
                    handler.job_queues[username] = Queue(username)
                if username not in handler.worker_pools:
                    handler.worker_pools[username] = []

                send_json_response(handler, 200, {"success": True, "token": token})
                return

    send_json_response(handler, 401, {"success": False})


def handle_get_register(handler: JobServerHandler, body: str) -> None:
    """Create a basic form for submitting a register request."""
    handler.send_response(200)
    handler.send_header("Content-type", "text/html")
    handler.end_headers()
    handler.wfile.write(b"""
    <html>
        <head>
            <title>Register</title>
        </head>
        <body>
            <form action="/api/register" method="POST">
                <input type="text" name="username" placeholder="Username" />
                <input type="password" name="password" placeholder="Password" />
                <input type="submit" value="Register" />
            </form>
        </body>
    </html>
    """)
    return


def handle_register(handler: JobServerHandler, body: str) -> None:
    """Handle a register request."""
    # Get the username and password from the body
    # This might be a query string or a json string
    if "username=" in body:
        body_dict = dict(qc.split("=") for qc in body.split("&"))
    else:
        body_dict = json.loads(body)
    username: str = body_dict["username"]
    password: str = body_dict["password"]

    # Get the users from the environment variable
    users_envvar: str | None = os.getenv('USERS')
    assert users_envvar is not None, "USERS environment variable not set"
    users: list[str] = users_envvar.split(',')

    # Check if the user exists
    for user in users:
        user_name, user_hashed_password = user.split(':')
        if user_name == username:
            send_json_response(handler, 401, {"success": False})
            return

    # Hash the password
    hashed_pass: str = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    # Add the user to the environment variable
    os.environ['USERS'] = users_envvar + "," + username + ":" + hashed_pass
    send_json_response(handler, 200, {"success": True})


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


def handle_get_jobs(handler: JobServerHandler, worker_id: str) -> None:
    assert handler.current_user is not None, "User not logged in"
    # get the query string
    query: dict[str, str] = {}
    if "?" in handler.path:
        query_string: str | None = handler.path.split("?")[1]
        # ternary operator to check if there is a query string
        if query_string is not None:
            query = dict(qc.split("=") for qc in query_string.split("&"))
    # get the assigned_to parameter
    assigned_to: str | None = query.get("assigned_to", None)
    # filter the job queue
    if assigned_to is not None:
        response = [job.to_json() for job in handler.job_queues[handler.current_user] if job.assigned_to == assigned_to]
    else:
        response = [job.to_json() for job in handler.job_queues[handler.current_user]]
    # return the job queue
    send_json_response(handler, 200, {"jobs": response})


def handle_add_job(handler: JobServerHandler, job_str: str) -> None:
    """Add a job to the queue."""
    assert handler.current_user is not None, "User not logged in"

    # if its a query string, parse it
    if "octave_query=" in job_str:
        body = dict(qc.split("=") for qc in job_str.split("&"))
        # remove the octave_query key
        body.pop("octave_query")
        job = Job(**body)
    else:  # otherwise, its a json string
        # convert the string to a Job object
        job = Job(**json.loads(job_str))

    handler.job_queues[handler.current_user].append(job)
    send_json_response(handler, 200, {"success": True})


def handle_add_worker(handler: JobServerHandler, worker_str: str) -> None:
    """Add a worker to the queue."""
    assert handler.current_user is not None, "User not logged in"
    # if its a query string, parse it
    if "octave_query=" in worker_str:
        body = dict(qc.split("=") for qc in worker_str.split("&"))
        # remove the octave_query key
        body.pop("octave_query")
        # remove anything not in the Worker constructor
        body: dict[str, str] = {key: value for key, value in body.items() if key in Worker.__init__.__code__.co_varnames}
        worker = Worker(**body)
    else:  # otherwise, its a json string
        # convert the string to a Job object
        worker = Worker(**json.loads(worker_str))

    # add the worker to the registry
    print(worker.to_json())
    handler.worker_pools[handler.current_user].append(worker)
    send_json_response(handler, 200, {"success": True})


def handle_get_workers(handler: JobServerHandler, worker_id: str) -> None:
    """Get a worker from the registry."""
    assert handler.current_user is not None, "User not logged in"
    # get the worker
    workers: list[Worker] = handler.worker_pools[handler.current_user]
    print(workers)
    if len(worker_id) == 0:
        # Convert the entire list to json
        wlist_json = [worker.to_json() for worker in workers]
        r = {"workers": wlist_json}
        print(r)
        send_json_response(handler, 200, r)
        return
    else:
        worker: Worker | None = next((worker for worker in workers if worker.worker_id == worker_id), None)
        if worker is None:
            send_json_response(handler, 200, {"worker": None})
            return
        # return the worker
        send_json_response(handler, 200, {"worker": worker.to_json()})


def handle_add_queue(handler: JobServerHandler, queue_str: str) -> None:
    """Create a new queue."""
    assert handler.current_user is not None, "User not logged in"
    # if its a query string, parse it
    if "octave_query=" in queue_str:
        body = dict(qc.split("=") for qc in queue_str.split("&"))
        # remove the octave_query key
        body.pop("octave_query")
        # remove anything not in the Worker constructor
        body: dict[str, str] = {key: value for key, value in body.items() if key in Worker.__init__.__code__.co_varnames}
        queue = Queue(**body)
    else:  # otherwise, its a json string
        # convert the string to a Job object
        queue = Queue(**json.loads(queue_str))

    # add the queue to the registry
    handler.job_queues[handler.current_user] = queue
    send_json_response(handler, 200, {"success": True})


def handle_get_queue(handler: JobServerHandler, queue_id: str) -> None:
    """Get a queue from the registry."""
    assert handler.current_user is not None, "User not logged in"
    # get the queue
    queue: Queue = handler.job_queues[handler.current_user]
    # return the queue
    send_json_response(handler, 200, {"queue": queue.to_json()})


def handle_get_sites(handler: JobServerHandler, worker_id: str) -> None:
    pass


def handle_add_site(handler: JobServerHandler, worker_id: str) -> None:
    pass
