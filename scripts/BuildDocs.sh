#!/bin/bash

# Get current working directory
startDir=$(pwd)

# Set the location to this file's directory
here="$(dirname "$(readlink -f "$0")")"
cd "$here/../doc" || exit

# Generate Sphinx source files from code in the repository
# Output directory: 'root/doc/source'
# Input directory: 'root/src'
sphinx-apidoc -o source/ ..

# Build the HTML documentation
# Build html files
# Sphinx source directory: 'root/doc/source' (contains conf.py)
# Output directory: 'root/doc/build'
sphinx-build -M html source build

# Copy the HTML files to the output directory
cp -r build/html/* ../output/doc/

# Reset the location
cd "$startDir" || exit
