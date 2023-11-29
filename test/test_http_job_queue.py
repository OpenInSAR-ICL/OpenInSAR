# test_server.py
import os
import pytest
import requests
import json
import bcrypt
from typing import Generator, Any
from pathlib import Path
from .TestUtilities import lock_resource
from .test_octave_connection import found_octave
from src.openinsar_core.job_handling.HttpJobServer import HttpJobServer
from src.openinsar_core.job_handling.Endpoints import endpoints
import subprocess
assert lock_resource is not None  # Just to shut up the linters who think its unused


BASE_PORT = 8888
BASE_ADDRESS = f'http://localhost:{BASE_PORT}'
BASE_URL = f'{BASE_ADDRESS}'


@pytest.fixture
def server(lock_resource) -> Generator[HttpJobServer, None, None]:
    """Launch the server, return the server object"""
    # Set a test username and password in environment variables
    test_pass = 'test_password'
    # Hash the password
    hashed_pass: str = bcrypt.hashpw(test_pass.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    os.environ['USERS'] = "test_user:" + str(hashed_pass)
    server_process = HttpJobServer(port=BASE_PORT)
    server_process.launch()
    yield server_process
    server_process.stop()


@pytest.fixture
def headers(server) -> dict[str, str]:
    """Log in to the server and return the token."""
    # Assuming the login endpoint is at '/login' and it accepts POST requests
    # with a JSON body containing 'username' and 'password'
    response = requests.post(f'{BASE_URL}/api/login', json={'username': 'test_user', 'password': 'test_password'})
    assert response.status_code == 200
    assert 'token' in response.json()
    token: str = response.json()['token']
    return {'Authorization': f'Bearer {token}'}


def test_route_consistency():
    """Check that the routes are consistent with the OpenAPI specification.
    The specification should be found in spec/openapi.json
    """
    openapi_file = 'spec/openapi.json'
    # Check the file exists with pathlib
    assert Path(openapi_file).is_file(), "OpenAPI specification file not found"
    # Load the file
    openapi_spec: dict[str, dict[str, Any]] | None = None
    with open(openapi_file, 'r') as f:
        openapi_spec = json.load(f)
    assert openapi_spec is not None, "Failed to load OpenAPI specification file"

    http_methods: list[str] = ['GET', 'POST', 'PUT', 'DELETE']

    for route in openapi_spec['paths'].keys():
        assert route in endpoints.keys(), f"Route {route} not found in server"

        # Check the specified methods are handled
        specified_methods = list(m.upper() for m in openapi_spec['paths'][route].keys() if m.upper() in http_methods)
        available_methods = list(endpoints[route].keys())
        for m in specified_methods:
            assert m.upper() in available_methods, f"Method {m} not found in server for route {route}"


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_server(server: HttpJobServer):
    """Test setting up the server and receiving a message"""
    response = requests.get(BASE_ADDRESS)
    assert response.status_code == 200


# @pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
# def test_no_queues(server: HttpJobServer):
#     """Test that the server starts with no queues"""
#     response = requests.get(f'{BASE_URL}/queues')
#     assert response.status_code == 200
#     assert 'queues' in response.json()
#     assert len(response.json()['queues']) == 0


# @pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
# def test_add_queue(server: HttpJobServer):
#     """Test adding a queue to the server"""
#     response = requests.post(f'{BASE_URL}/queues', json={'queue_id': 'queue1'})
#     assert response.status_code == 200
#     assert 'success' in response.json().keys()
#     # Check that the queue was added
#     response = requests.get(f'{BASE_URL}/queues')
#     assert response.status_code == 200
#     assert 'queues' in response.json()
#     assert len(response.json()['queues']) == 1

@pytest.fixture
@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_job_server(server: HttpJobServer, headers: dict[str, str]) -> None:
    """Test Job api"""
    # Start with an empty job list
    response: requests.Response = requests.get(f'{BASE_URL}/api/jobs', headers=headers)
    assert response.status_code == 200, "Request failed"
    assert len(response.content)> 0, "Response was empty"
    assert 'jobs' in response.json(), "Response did not contain jobs json"

    # Add a job
    response: requests.Response = requests.post(f'{BASE_URL}/api/jobs', json={'assigned_to': 'user1', 'task': 'Task 1'}, headers=headers)
    assert response.status_code == 200
    assert 'success' in response.json().keys()

    # Check that the job was added
    response: requests.Response = requests.get(f'{BASE_URL}/api/jobs', headers=headers)
    assert response.status_code == 200
    assert 'jobs' in response.json()
    assert len(response.json()['jobs']) == 1
    assert response.json()['jobs'][0]['assigned_to'] == 'user1'


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_get_jobs_assigned_to_user(server: HttpJobServer, headers: dict[str, str], test_job_server: None):
    # Assuming the server starts with an empty job list
    requests.post(f'{BASE_URL}/api/jobs', json={'assigned_to': 'user2', 'task': 'Task 2'}, headers=headers)
    requests.post(f'{BASE_URL}/api/jobs', json={'assigned_to': 'user3', 'task': 'Task 3'}, headers=headers)

    response = requests.get(f'{BASE_URL}/api/jobs?assigned_to=user2', headers=headers)
    assert response.status_code == 200
    assert 'jobs' in response.json()
    assert len(response.json()['jobs']) == 1
    assert response.json()['jobs'][0]['assigned_to'] == 'user2'


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_get_jobs_nonexistent_user(server: HttpJobServer, headers: dict[str, str]):
    response = requests.get(f'{BASE_URL}/api/jobs?assigned_to=nonexistent_user', headers=headers)
    assert response.status_code == 200
    assert 'jobs' in response.json()
    assert len(response.json()['jobs']) == 0


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_deployment_via_main(lock_resource, headers: dict[str, str]):
    """Test deployment via the main method"""
    import sys
    # override command line arguments
    sys.argv = ["HttpJobServer", "local", "use_threading=True", "port=" + str(BASE_PORT)]
    # import the main method
    from src.openinsar_core.job_handling.HttpJobServer import main
    # run the main method
    server_inst: HttpJobServer = main()

    # send a request to the server
    response = requests.get(f'{BASE_URL}/api/jobs', headers=headers)
    assert response.status_code == 200
    assert 'jobs' in response.json()

    # stop the server
    server_inst.stop()


@pytest.mark.skipif(not found_octave(), reason="Octave not found on command line")
@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_send_job_via_octave(lock_resource, headers: dict[str, str]):
    # Set environment variables
    os.environ['OI_USERNAME'] = 'test_user'
    os.environ['OI_PASSWORD'] = 'test_password'
    os.environ['OI_SERVER'] = BASE_ADDRESS + '/api'
    os.environ['OI_MESSENGER_TYPE'] = 'http'
    octave_path = 'octave-cli'
    command = """
    setenv("OI_USERNAME", "test_user");
    setenv("OI_PASSWORD", "test_password");
    setenv("OI_SERVER", "http://localhost:8888/api");
    setenv("OI_MESSENGER", "http");
    cd ./output/;
    w = WorkerClient()
    """
    # Remove newlines
    command: str = command.replace('\n', ' ')
    try:
        o: str = subprocess.check_output([octave_path, "--norc", "--eval", command], stderr=subprocess.STDOUT, shell=True).decode('utf-8')
    except subprocess.CalledProcessError as e:
        print(e.output)
        o = e.output.decode('utf-8')
    assert 'success' in o, "Octave did not successfully communicate with the server"
    assert 'token' in o, 'Octave did not log in'
