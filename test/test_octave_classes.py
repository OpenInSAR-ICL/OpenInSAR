import os
import pytest
import subprocess
from .test_octave_connection import OCTAVE_RUN_COMMAND, FOUND_OCTAVE

OCTAVE_TEST_DIR = './test/octave/'
SET_CWD_HERE_OPTION = '--norc'

def get_octave_tests() -> list[str]:
    assert os.path.isdir(OCTAVE_TEST_DIR), f"Octave test directory not found: {OCTAVE_TEST_DIR}"
    octave_files = [f for f in os.listdir(OCTAVE_TEST_DIR) if f.endswith('.m')]
    return octave_files


@pytest.mark.skipif(not FOUND_OCTAVE, reason="Octave not found on command line")
@pytest.mark.parametrize("test_file", get_octave_tests())
def test_octave_file(test_file):
    print(f"Running octave test: {test_file}")
    # capture stdout and stderr from the system call
    try:
        o = subprocess.check_output([OCTAVE_RUN_COMMAND, SET_CWD_HERE_OPTION, f"{OCTAVE_TEST_DIR}{test_file}"], shell=True)
    except subprocess.CalledProcessError as e:
        print(f"Octave test failed: {test_file}")
        print(e.output)
        raise e
    # Decode the output
    o = o.decode('utf-8')
    # Check if the output is correct
    assert 'error' not in o.lower(), "Octave test failed"
