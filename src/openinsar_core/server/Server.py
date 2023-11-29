"""Combine all the component server handlers into one server."""
from __future__ import annotations
import sys
from typing import TYPE_CHECKING
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler
# from socketserver import _RequestType, BaseServer
# from src.openinsar_core.job_handling import HttpJobServer
# from src.openinsar_core.job_handling.Endpoints import Endpoints
from src.openinsar_core.server.DeploymentConfig import DeploymentConfig, for_local, for_render
from src.openinsar_core.server.ThreadedHttpServer import ThreadedHttpServer
from src.openinsar_core.server.SinglePageAppServer import SinglePageApplicationHandler
from src.openinsar_core.job_handling.HttpJobServer import JobServerHandler


if TYPE_CHECKING:
    class OiServerType(ThreadedHttpServer):
        api_handler: JobServerHandler
        spa_handler: SinglePageApplicationHandler


class CustomHandler(SimpleHTTPRequestHandler):
    """Switches the handler based on the path."""
    server: OiServerType

    def do_GET(self):
        if self.path.startswith('/doc/') or self.path.startswith('doc/'):
            # We need to serve the docs from the root directory
            self.path = self.path.replace('/doc/', '../doc/')
            super().do_GET()
        if self.path.endswith('.js') or self.path.endswith('.css') or self.path.endswith('.ico') or self.path.endswith('.png'):
            self.server.spa_handler.do_GET()
        if self.path.startswith('/api/'):
            self.server.api_handler.do_GET()
        elif self.path.startswith('/') or self.path == '':
            self.server.spa_handler.do_GET()

    def do_POST(self):
        if self.path.startswith('/api/'):
            self.server.api_handler.do_POST()
        elif self.path.startswith('/') or self.path == '':
            self.server.spa_handler.do_GET()


class OiServer(ThreadedHttpServer):
    def __init__(self, *args, **kwargs) -> None:
        self.api_handler: JobServerHandler
        self.spa_handler: SinglePageApplicationHandler
        self.handler: JobServerHandler
        # filter out any kwargs that are not accepted by the ThreadedHttpServer
        kwargs = {key: value for key, value in kwargs.items() if key in ThreadedHttpServer.__init__.__code__.co_varnames}
        super().__init__(*args, handler=JobServerHandler, **kwargs)


def main() -> OiServer:
    """
    Example usage. Runs the server on the specified platform:
    - render: Run the server on render.com
        >  python -m src.openinsar_core.HttpJobServer render
    - local: Run the server locally
        >  python -m src.openinsar_core.HttpJobServer local
    """

    # Get target platform from command line arguments
    if len(sys.argv) > 1:
        platform = sys.argv[1]
    else:
        platform = "local"

    # Switch the config based on the platform
    config: DeploymentConfig = DeploymentConfig()
    if platform == "render":
        config = for_render()
    elif platform == "local":
        config = for_local()
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
    server = OiServer(config=config)
    # Start the server
    server.launch(directory='./output/')

    return server  # to keep the server alive if we're running in a thread


if __name__ == "__main__":
    # Set the 'USERS' env var to get things started
    import os
    os.environ['USERS'] = 'test_user:this_pass_wont_work'
    main()
