# BuildDocs.ps1: Build the documentation

# Get cwd
$startDir = Get-Location

# Set the location to this file's directory
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Activate the virtual environment
. $here/../venv/Scripts/activate

# Set the location to the doc directory
Set-Location $here/../doc

# sphinx-apidoc: Generate Sphinx source files from code in the repository
#   -o source/: Output directory ('root/doc/source')
#   ../src/: Input directory ('root/src')
sphinx-apidoc -o source/ ../src
sphinx-apidoc -o source/ ../test

# sphinx-build: Build the html documentation
#   -M html: build html files
#   source: Sphinx source directory ('root/doc/source', contains conf.py)
#   build: Output directory ('root/doc/build')
sphinx-build -M html source build -E -a

# Remove the old html files
if (Test-Path ../output/doc/) {
    Remove-Item -Path ../output/doc/ -Recurse -Force
}

# Copy the html files to the output directory
Copy-Item -Path build/html/ -Destination ../output/doc/ -Recurse -Force

# Reset the location
Set-Location $startDir
