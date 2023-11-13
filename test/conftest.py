"""
pytest configuration file. See :ref:`pytest:conftest`. This module is loaded automatically by pytest before running any tests, and then
:py:func:`pytest_configure` is called.
"""


def add_executables_to_path():
    """
    Adds the virtual environment executables to the system path.
    For example, sphinx, sphinx-apidoc, pip, etc.
    There's an issue with VS Code pytest not finding these, this is a workaround.
    """
    import os
    if os.name == "nt":
        sphinx_dir = os.path.join(os.getcwd(), "venv", "Scripts")
    else:  # Assume unix
        sphinx_dir = os.path.join(os.getcwd(), "venv", "bin")

    # Check the venv directory exists
    assert os.path.isdir(sphinx_dir), "Failed to find venv directory"

    # Add the venv/bin directory to the PATH
    os.environ["PATH"] += os.pathsep + sphinx_dir


def pytest_configure(config):
    """
    Called after command line options have been parsed and
    all plugins and initial conftest files been loaded.
    """
    add_executables_to_path()
