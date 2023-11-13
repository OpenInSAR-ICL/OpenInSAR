# test_server.py

import pytest
import requests
from .TestUtilities import lock_resource


assert lock_resource is not None  # Just to shut up the linters who think its unused


BASE_PORT = 8888
BASE_ADDRESS = f'http://localhost:{BASE_PORT}'
BASE_URL = f'{BASE_ADDRESS}'


@pytest.fixture
def server(lock_resource):
    """Launch the server, return the server object"""
    from src.openinsar_core.HttpJobServer import HttpJobServer
    server_process = HttpJobServer(port=BASE_PORT)
    server_process.launch()
    yield server_process
    server_process.stop()


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_server(server):
    """Test setting up the server and receiving a message"""
    response = requests.get(BASE_ADDRESS)
    assert response.status_code == 200


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_post_job(server):
    response = requests.post(f'{BASE_URL}/add_job', json={'assigned_to': 'user1', 'task': 'Task 1'})
    assert response.status_code == 200
    assert response.json()['message'] == 'Job posted successfully'


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_get_jobs_all(server):
    response = requests.get(f'{BASE_URL}/jobs')
    assert response.status_code == 200, "Request failed"
    assert len(response.content) > 0, "Response was empty"
    assert 'jobs' in response.json(), "Response did not contain jobs json"


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_get_jobs_assigned_to_user(server):
    # Assuming the server starts with an empty job list
    requests.post(f'{BASE_URL}/add_job', json={'assigned_to': 'user2', 'task': 'Task 2'})
    requests.post(f'{BASE_URL}/add_job', json={'assigned_to': 'user3', 'task': 'Task 3'})

    response = requests.get(f'{BASE_URL}/jobs?assigned_to=user2')
    assert response.status_code == 200
    assert 'jobs' in response.json()
    assert len(response.json()['jobs']) == 1
    assert response.json()['jobs'][0]['assigned_to'] == 'user2'


@pytest.mark.parametrize("lock_resource", ["port" + str(BASE_PORT)], indirect=True, ids=["Use port " + str(BASE_PORT)])  # Mutex for the port
def test_get_jobs_nonexistent_user(server):
    response = requests.get(f'{BASE_URL}/jobs?assigned_to=nonexistent_user')
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
    response = requests.get(f'{BASE_URL}/jobs')
    assert response.status_code == 200
    assert 'jobs' in response.json()

    # stop the server
    server_inst.stop()
