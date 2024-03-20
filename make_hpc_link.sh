#!/bin/bash

# Set the source and target paths
source_path=~/../projects/insardatastore/ephemeral/$USER

target_path=~/work

# Resolve the absolute paths
source_path=$(realpath "$source_path")
target_path=$(realpath "$target_path")

echo $source_path
echo $target_path

# Create the symbolic link
ln -s "$source_path" "$target_path"
echo "Symbolic link created at $target_path"
