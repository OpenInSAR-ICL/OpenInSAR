"""
test_octave_connection.py
-------------------------
Check if octave is installed and can be called from python.
"""

import pytest
import subprocess
import logging
import requests
from src.openinsar_core.HttpJobServer import HttpJobServer
from typing import Generator, Any


JOB_SERVER_PORT = 8080
OCTAVE_RUN_COMMAND = 'octave-cli'


def found_octave() -> bool:
    """Check if Octave is installed on the host system."""
    try:
        subprocess.check_output([OCTAVE_RUN_COMMAND, "--version"], shell=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


FOUND_OCTAVE: bool = found_octave()


@pytest.mark.skipif(not found_octave(), reason="Octave not found on command line")
@pytest.fixture(scope="module", autouse=True)
def server() -> Generator[HttpJobServer, Any, None]:
    """Launch the server, return the server object"""
    from src.openinsar_core.HttpJobServer import HttpJobServer
    server_process = HttpJobServer(port=JOB_SERVER_PORT)
    server_process.launch()
    yield server_process
    server_process.stop()


@pytest.mark.skipif(not found_octave(), reason="Octave not found on command line")
def test_command_octave() -> None:
    """Call Octave script from python. Skips if octave-cli is not available on the command line."""

    # Get the path to the octave binary
    command = "disp('hello from octave')"

    # Run the octave command and decode the output
    o: str = subprocess.check_output([OCTAVE_RUN_COMMAND, "--eval", command], shell=True).decode('utf-8')

    # Check if the output is correct
    assert 'hello from octave' in o.lower(), "Octave did not respond as expected"


@pytest.mark.skipif(not found_octave(), reason="Octave not found on command line")
def test_worker_client() -> None:
    """Call the worker client. See if it is behaving properly."""
    # Get the path to the octave binary
    command = """
    cd ./output/;
    w = WorkerClient()
    """
    # Remove newlines
    command: str = command.replace('\n', ' ')

    # Run the octave command
    try:
        o: str = subprocess.check_output([OCTAVE_RUN_COMMAND, "--norc", "--eval", command], stderr=subprocess.STDOUT, shell=True).decode('utf-8')
    except subprocess.CalledProcessError as e:
        o = e.output.decode('utf-8')
        logging.warning(e.output)

    logging.getLogger().error(o)

    # Check if the output is correct
    assert not any(x in o.lower() for x in ['error', 'undefined']), "Octave worker client did not respond as expected"
    assert 'WorkerClient' in o, 'WorkerClient not found in output'


@pytest.mark.skipif(not found_octave(), reason="Octave not found on command line")
def test_http_communication(server: HttpJobServer) -> None:
    """Call the worker client. See if it is behaving properly."""
    # Add a job to the server
    worker_id = 'kevin'
    task = 'test_task'

    response: requests.Response = requests.post(f'http://localhost:{JOB_SERVER_PORT}/add_job', json={'assigned_to': worker_id, 'task': task})
    assert response.status_code == 200, "Request failed"

    # Get the path to the octave binary
    command = f"""
    cd ./output/;
    w = WorkerClient();
    server = "localhost:{JOB_SERVER_PORT}";
    w.workerInfo.id = '{worker_id}';
    w.messenger = OI.HttpMessenger(server);
    w.main();
    """
    # Remove newlines and python 4-space indentation
    command: str = command.replace('\n', ' ').replace('    ', ' ')

    # Run the octave command. It should get a job from the server.
    try:
        o: str = subprocess.check_output([OCTAVE_RUN_COMMAND, "--norc", "--eval", command], stderr=subprocess.STDOUT, shell=True).decode('utf-8')
    except subprocess.CalledProcessError as e:
        o = e.output.decode('utf-8')
        logging.warning(e.output)

    # Is the type of output correct?
    assert isinstance(o, str), "Output is not a string"
    # Check that the task was found in the output
    assert task.lower() in o.lower(), "Task not found in output"

    # Get the job from the server
    response = requests.get(f'http://localhost:{JOB_SERVER_PORT}/get_jobs', json={'assigned_to': worker_id})
    assert response.status_code == 200, "Request failed"

    def match(j) -> bool:
        return j['assigned_to'] == worker_id and j['task'] == task
    assert any(match(j) for j in response.json()['jobs']), "Task not properly assigned to worker"
