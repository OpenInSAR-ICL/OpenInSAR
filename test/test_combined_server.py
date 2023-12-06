"""Test a server hosting both the API and the SPA."""
import requests
import pytest
import src.openinsar_core.server.DeploymentConfig as DeploymentConfigs
from src.openinsar_core.server.Server import main  # Import the function to create the server
from typing import Generator, Any
from time import sleep

_TEST_PORT = 8000
_TEST_URI = f"http://localhost:{_TEST_PORT}"


@pytest.fixture(scope="module")
def server():
    """Fixture to start and stop the server."""
    config = DeploymentConfigs.for_local()
    config.port = _TEST_PORT
    config.use_threading = True
    server = main()  # Start the server
    yield server
    server.stop()  # Stop the server after all tests in the module are completed


def test_combined_server(server) -> None:
    """Test the combined server."""
    # Test that the index page is serving the SPA
    while True:
        sleep(.1)
    response = requests.get(_TEST_URI)
    assert response.status_code == 200
    assert "Vue" in response.text

    # Test that the /api/ path is serving the API
    response = requests.get(_TEST_URI + "/api/info")
    assert response.status_code == 200
    assert "version" in response.json()
