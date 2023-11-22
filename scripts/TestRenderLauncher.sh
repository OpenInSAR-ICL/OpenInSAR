#!/bin/bash
help_message=$(cat <<EOH
Launch a matlab process on the ICL HPC system.
Usage:
    LaunchMatlabWorker.sh [options] <command>
Options:
    -h, --help
        Display this help message and exit.
    -d, --directory <directory>
        Specify the directory to start MATLAB in.
        Default: $HOME/OpenInSAR
    -c, --num-cores <num>
        Specify the number of CPU cores to use per worker.
        Default: 4
    -n, --num-workers <num>
        Specify the number of MATLAB workers to launch.
        Default: 2
    -m, --memory-per-core <memory>
        Specify the memory per core.
        Default: 4GB
    -t, --target <target>
        Specify path to the target executable to launch. This should be relative to the directory of this script.
        Default: ./scripts/LaunchMatlabWorker.sh
    -e, --eval <command>
        Specify a command to evaluate in MATLAB. The command has to be really basic (a single line, no newlines, no double quotes, no single quotes). This is due to some issues passing arguments to MATLAB via the PBS system.
        Suggestions are to use the name of a script, class or function, and use --directory to specify the location of this code.
        Default: disp('Hello from MATLAB!')
    -w, --walltime <walltime>
        Specify the walltime for the job.
        Default: 00:10:00
EOH
)

set -e # exit on error


# Set default values
set_defaults() {
    # Get the directory path of the current script
    current_directory=$(dirname "$(readlink -f "$0")")

    # Set default values
    start_directory=$current_directory/../output

    num_workers=99
    num_cores=4
    memory_per_core="4GB"
    walltime="00:05:00"
    command="RenderClient"
    job_name="OpenInSAR_$(date +%b%d_%Hh%Mm)"
    # Target executable to launch, relative to this script
    target="TestRenderWorker.sh"

    # Get the absolute path of the target executable
    target_filepath=$(realpath "$current_directory/$target")
    # Get the absolute path of the start directory
    start_directory=$(realpath "$start_directory")
}

# Function to check if the runPath exists
check_start_directory() {
    if [ ! -d "$start_directory" ]; then
        echo "Error: Directory '$start_directory' does not exist or is not accessible."
        exit 1
    fi
}

# Function to check if the command is valid
check_command() {
    # flag to print usage message
    do_print_usage=0

    # Check the command is not empty
    if [ -z "$command" ]; then
        echo "Error: No command specified."
        do_print_usage=1
    fi
    # There can't be any newlines in the command
    if [[ "$command" == *$'\n'* ]]; then
        echo "Error: Command cannot contain newlines."
        do_print_usage=1
    fi
    # There can't be any double quotes in the command
    if [[ "$command" == *"\""* ]]; then
        echo "Error: Command cannot contain double quotes."
        do_print_usage=1
    fi
    # There can't be any single quotes in the command
    if [[ "$command" == *"'"* ]]; then
        echo "Error: Command cannot contain single quotes."
        do_print_usage=1
    fi

    # If we hit a snag, show help and exit
    if [ "$do_print_usage" -eq 1 ]; then
        echo "$help_message"
        exit 1
    fi
}

# Help message
help() {
	echo $help_message
	exit 0
}

parse_arguments() {
    # Parse command line arguments
    
    set_defaults
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
            -e|--eval)
                command="$2"
                shift
                ;;
            -m|--memory-per-core)
                memory_per_core="$2"
                shift
                ;;
            -s|--silent)
                silent=1
                ;;
            -w|--walltime)
                walltime="$2"
                shift
                ;;
            -t|--target)
                target_filepath="$2"
                shift
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

echo_config() {
    # Echo the configuration
    echo "Configuration:"
    echo "    Job name: $job_name"
    echo "    Start directory: $start_directory"
    echo "    Number of workers: $num_workers"
    echo "    Number of cores per worker: $num_cores"
    echo "    Memory per core: $memory_per_core"
    echo "    Walltime: $walltime"
    echo "    Command: $command"
}

launch_workers() {
    # Launch MATLAB workers
    echo "Launching $num_workers MATLAB workers..."
 qsub -N $job_name -lselect=1:ncpus=$num_cores:mem=$memory_per_core -lwalltime=$walltime -J 1-$num_workers -v ICL_LAUNCHER_ARG_START_DIRECTORY=$start_directory,ICL_LAUNCHER_ARG_NUM_CORES=$num_cores,ICL_LAUNCHER_ARG_NUM_WORKERS=$num_workers,ICL_LAUNCHER_ARG_COMMAND=$command, $target_filepath
}

main() {
    # Check the start directory exists
    check_start_directory
    # Echo the configuration if silent is not set
    if [ -z "$silent" ]; then
        echo_config
    fi
    # Check the command is correct format
    check_command
    # Start MATLAB
    launch_workers
}

# Script entry point:
parse_arguments "$@"
main