#!/bin/bash

# Basic description of the script
echo "This script processes Sentinel-1 download links and removes files that do not match from the input directory."

# Default paths
DEFAULT_LINKS_FOLDER="Sizewell/work"
DEFAULT_LINKS_FILE="Sentinel1DownloadList.txt"
DEFAULT_DIRECTORY="input/"

# Dry run flag
DRY_RUN=true

# Usage function
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "This script reads Sentinel-1 download links from a file and checks for matching .zip and .safe files in the input directory."
  echo "By default, it performs a dry run, simulating file removals without actually deleting them."
  echo ""
  echo "Options:"
  echo "  --dry-run                Perform a dry run (default). Only prints actions without removing files."
  echo "  --remove             Perform the actual removal of files."
  echo "  --links-folder FOLDER    Specify the folder containing the links file (default: $DEFAULT_LINKS_FOLDER)."
  echo "  --help                   Show this help message."
  exit 1
}

# If no arguments are provided, show the help message
if [ $# -eq 0 ]; then
  usage
fi

# Parse command-line arguments
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --remove)
      DRY_RUN=false
      ;;
    --links-folder)
      LINKS_FOLDER="$2"
      shift
      ;;
    --help)
      usage
      ;;
    *)
      echo "Invalid option: $arg"
      usage
      ;;
  esac
done

# Set links file folder, default to $DEFAULT_LINKS_FOLDER if not set
LINKS_FOLDER=${LINKS_FOLDER:-$DEFAULT_LINKS_FOLDER}

# Paths
LINKS_FILE="$LINKS_FOLDER/$DEFAULT_LINKS_FILE"
DIRECTORY="$DEFAULT_DIRECTORY"

# Check if the links file exists
if [ ! -f "$LINKS_FILE" ]; then
  echo "Error: Links file '$LINKS_FILE' not found."
  exit 1
fi

# Load the links file once and extract identifiers (filename without .zip)
valid_identifiers=()
while IFS= read -r link; do
  # Extract the file identifier (between last '/' and '.zip')
  if [[ "$link" =~ /([^/]+)\.zip$ ]]; then
    valid_identifiers+=("${BASH_REMATCH[1]}")
  fi
done < "$LINKS_FILE"

# Cache the result of ls in a variable (files in input/)
files_in_directory=$(ls -1 "$DIRECTORY")

# Initialize a counter for removed files
match_count=0

# Loop through each file in the input directory
for full_name in $files_in_directory; do
  # Extract the filename without extension (.zip or .SAFE)
  file_basename=$(basename "$full_name" .zip)
  file_basename=$(basename "$file_basename" .SAFE)

  # Check if the file matches any valid identifier
  match_found=false
  for identifier in "${valid_identifiers[@]}"; do
    if [[ "$file_basename" == "$identifier" ]]; then
      match_found=true
      break
    fi
  done

  # If no match was found, we want to remove this file
  if [ "$match_found" = false ]; then
    match_count=$((match_count + 1))
    echo "No match found for: $full_name"
    
    if [ "$DRY_RUN" = true ]; then
      echo "Dry run: Not removing $DIRECTORY$full_name"
    else
      rm -r "$DIRECTORY$full_name"
      echo "Removed: $DIRECTORY$full_name"
    fi
  fi
done

# Output the total number of files removed
echo "Total files removed: $match_count"

