#!/bin/bash
help_message=$(cat <<EOH
=====================
LaunchMatlabWorker.sh
=====================

This script launches a MATLAB process on the ICL HPC system.

The PBS system is very awkward for passing command line arguments. Therefore 
it is easier to set the arguments as environment variables. See the help text 
for variables below.

Usage:
    # Pass arguments on the command line:
    LaunchMatlabWorker.sh [options]

    # Or use environment variables:
    ICL_LAUNCHER_ARG_[ARGUMENT_NAME] = [ARGUMENT_VALUE] 
    LaunchMatlabWorker.sh

Options:
    -h, --help 
        Display this help message and exit.
    -c, --num-cores <num>
        Specify the number of CPU cores to use per worker.
        Default: 1
        Environment variable: ICL_LAUNCHER_ARG_NUM_CORES    
    -d, --directory <directory>
        Specify the directory to start MATLAB in.
        Default: $HOME/OpenInSAR
        Environment variable: ICL_LAUNCHER_ARG_START_DIRECTORY
    -e, --eval <command>
        Specify a command to evaluate in MATLAB.
        Default: disp('Hello from MATLAB!')
        Environment variable: ICL_LAUNCHER_ARG_COMMAND
    -i, --worker-index <num>
        Specify the worker index.
        Default: 0
        Environment variable: PBS_ARRAY_INDEX
    -n, --num-workers <num>
        Specify the number of MATLAB workers to launch.
        Default: 1
        Environment variable: ICL_LAUNCHER_ARG_NUM_WORKERS
    -s, --silent
        Do not echo contextual information.

EOH
)

# Get environmental arguments
load_args_from_environment() {
    start_directory="$ICL_LAUNCHER_ARG_START_DIRECTORY"
    num_workers="$ICL_LAUNCHER_ARG_NUM_WORKERS"
    num_cores="$ICL_LAUNCHER_ARG_NUM_CORES"
    command="$ICL_LAUNCHER_ARG_COMMAND"
    echo $ICL_LAUNCHER_ARG_COMMAND
    # worker_index is set by PBS as PBS_ARRAY_INDEX
    # worker_index="$ICL_LAUNCHER_ARG_WORKER_INDEX" 
    worker_index="$PBS_ARRAY_INDEX"
}

# Set default values
set_defaults() {
    # Set default values
    start_directory="$HOME/OI_ICL_FORK"
    num_workers=1
    num_cores=1
    worker_index=0
    command="disp(['Hello from MATLAB instance '"
    command+="num2str(WORKER_INDEX) ' of ' num2str(NUM_WORKERS) '"
    command+=" in ' pwd ' as start dir. ']);ls"
}

# Function to check if the runPath exists
check_start_directory() {
    if [ ! -d "$start_directory" ]; then
        echo "Error: Directory '$start_directory' does not exist or is not accessible."
        exit 1
    fi
}

# check we are running on a worker node
check_environment() {
    if [ -z "$PBS_ARRAY_INDEX" ]; then
        echo "Error: This script should only be run on a worker node."
        exit 1
    fi
}

# Load environment modules
load_modules() {
    echo "Not loading python"
    {
        module load matlab/R2021a 2>&1
    } || {
        echo "Error: Could not load MATLAB module."
        exit 1
    }
}

# Echo contextual information
echo_config() {
    echo "Start directory: $start_directory"
    echo "Number of workers: $num_workers"
    echo "Number of cores per worker: $num_cores"
    echo "Worker index: $worker_index"
    echo "Command: "$command""
    echo "Current directory: $(pwd)"
}

# Function to start MATLAB execution
start_matlab() {
    cd "$start_directory" || exit 1

    echo "Starting MATLAB in $(pwd)..."
    set_worker_index="WORKER_INDEX=$worker_index;"
    set_num_workers="NUM_WORKERS=$num_workers;"
    mat_command=$set_worker_index$set_n_workers$command
    matlab -nodesktop -nosplash -noFigureWindows -prefersoftwareopengl -r "$mat_command"
}

# Help message
help() {
    echo "$help_message"
    exit 0
}

parse_arguments() {
    # Parse command line arguments
    set_defaults
    load_args_from_environment
    while [ $# -gt 0 ]; do
        echo "Processing argument: $1"  # Debugging statement   
        case "$1" in
            -h|--help)
                help ;;
            -d|--directory)
                start_directory="$2"
                shift
                ;;
            -n|--num-workers)
                num_workers="$2"
                shift
                ;;
            -c|--num-cores)
                num_cores="$2"
                shift
                ;;
            -i|--worker-index)
                worker_index="$2"
                shift
                ;;
            -e|--eval)
                command="$2"
                shift
                ;;
            -s|--silent)
                silent=1
                ;;
            --)
                shift
                break
                ;;
            *) echo "Error: Invalid argument '$1'"
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    # Check the start directory exists
    check_start_directory
    check_environment
    # Load environment modules

    load_modules
    # Echo contextual information unless silent flag is set
    if [ -z "$silent" ]; then
        echo_config
    fi
    # Start MATLAB
    start_matlab
}
# Script entry point:
parse_arguments "$@"
main