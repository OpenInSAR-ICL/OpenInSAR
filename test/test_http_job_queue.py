# test_server.py

import pytest
import requests
from .TestUtilities import lock_resource
from .test_octave_connection import found_octave
from src.openinsar_core.HttpJobServer import HttpJobServer
from typing import Generator
import subprocess
assert lock_resource is not None  # Just to shut up the linters who think its unused


BASE_PORT = 8888
BASE_ADDRESS = f'http://localhost:{BASE_PORT}'
BASE_URL = f'{BASE_ADDRESS}'


@pytest.fixture
def server(lock_resource) -> Generator[HttpJobServer, None, None]:
    """Launch the server, return the server object"""
    server_process = HttpJobServer(port=BASE_PORT)
    server_process.launch()
    yield server_process
    server_process.stop()


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_server(server: HttpJobServer):
    """Test setting up the server and receiving a message"""
    response = requests.get(BASE_ADDRESS)
    assert response.status_code == 200


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_no_queues(server: HttpJobServer):
    """Test that the server starts with no queues"""
    response = requests.get(f'{BASE_URL}/get_queue')
    assert response.status_code == 200
    assert 'queues' in response.json()
    assert len(response.json()['queues']) == 0


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_add_queue(server: HttpJobServer):
    """Test adding a queue to the server"""
    response = requests.post(f'{BASE_URL}/add_queue', json={'queue_id': 'queue1'})
    assert response.status_code == 200
    assert 'success' in response.json().keys()
    # Check that the queue was added
    response = requests.get(f'{BASE_URL}/get_queue')
    assert response.status_code == 200
    assert 'queues' in response.json()
    assert len(response.json()['queues']) == 1


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_post_job(server):
    response: Response = requests.post(f'{BASE_URL}/add_job', json={'assigned_to': 'user1', 'task': 'Task 1'})
    assert response.status_code == 200
    assert 'success' in response.json().keys()


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_get_jobs_all(server):
    response: Response = requests.get(f'{BASE_URL}/get_jobs')
    assert response.status_code == 200, "Request failed"
    assert len(response.content) > 0, "Response was empty"
    assert 'jobs' in response.json(), "Response did not contain jobs json"


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_get_jobs_assigned_to_user(server):
    # Assuming the server starts with an empty job list
    requests.post(f'{BASE_URL}/add_job', json={'assigned_to': 'user2', 'task': 'Task 2'})
    requests.post(f'{BASE_URL}/add_job', json={'assigned_to': 'user3', 'task': 'Task 3'})

    response = requests.get(f'{BASE_URL}/get_jobs?assigned_to=user2')
    assert response.status_code == 200
    assert 'jobs' in response.json()
    assert len(response.json()['jobs']) == 1
    assert response.json()['jobs'][0]['assigned_to'] == 'user2'


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_get_jobs_nonexistent_user(server):
    response = requests.get(f'{BASE_URL}/get_jobs?assigned_to=nonexistent_user')
    assert response.status_code == 200
    assert 'jobs' in response.json()
    assert len(response.json()['jobs']) == 0


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_deployment_via_main(lock_resource):
    """Test deployment via the main method"""
    import sys
    # override command line arguments
    sys.argv = ["HttpJobServer", "local", "use_threading=True", "port=" + str(BASE_PORT)]
    # import the main method
    from src.openinsar_core.HttpJobServer import main
    # run the main method
    server_inst = main()

    # send a request to the server
    response = requests.get(f'{BASE_URL}/get_jobs')
    assert response.status_code == 200
    assert 'jobs' in response.json()

    # stop the server
    server_inst.stop()


@pytest.mark.skipif(not found_octave(), reason="Octave not found on command line")
@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_send_job_via_octave(lock_resource):
    octave_path = 'octave-cli'
    command = """
    cd ./output/;
    w = WorkerClient()
    """
    # Remove newlines
    command = command.replace('\n', ' ')
    o = subprocess.check_output([octave_path, "--norc", "--eval", command], stderr=subprocess.STDOUT, shell=True)