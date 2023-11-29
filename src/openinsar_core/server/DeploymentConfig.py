class DeploymentConfig:
    def __init__(
            self,
            name: str = "default",
            port: int = 8765,
            host: str = "localhost",
            use_https: bool = False,
            use_threading: bool = True):
        self.name: str = name
        self.port: int = port
        self.host: str = host
        self.use_https: bool = use_https
        self.use_threading: bool = use_threading


def for_render():
    return DeploymentConfig(
        name="render",
        port=80,
        host="0.0.0.0",
        use_https=False,
        use_threading=False
    )


def for_local():
    return DeploymentConfig(
        name="local",
    )
