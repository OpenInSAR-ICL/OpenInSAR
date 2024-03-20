# Get the path of the cwd and this script


LASTDIR=$(pwd) || { echo "Failed to get current directory"; exit 1; }

thisScriptDir=$(dirname "${BASH_SOURCE[0]}")

echo "Original working directory: $LASTDIR"

# OI loads projects using a link file in the repository.
linkFileName='CurrentProject.xml'
linkFileLocation=$(realpath $thisScriptDir/../output/)
linkFilePath=$linkFileLocation/$linkFileName

# validate that we're on the ICL HPC
allHostNames=$(hostname -A)
if [[ $allHostNames != *"ic.ac.uk"* ]]; then
    echo -e "\033[1;33mThis may not work if you are not on the HPC cluster\033[0m"
    exit 1
fi

# read CurrentProject.xml
if [ -f $linkFilePath ]; then
    # get the filepath of the project file
    projectFile=$(grep -oPm1 "(?<=<relative_path>)[^<]+" $linkFilePath)
    # this is relative to the linkFileLocation, so we need to append that
    # first add a trailing slash to the linkFileLocation if it doesn't have one
    if [[ $linkFileLocation != */ ]]; then
        linkFileLocation="$linkFileLocation/"
    fi
    # we need to replace '$USERNAME' with the actual username
    projectFile=$(echo $projectFile | sed "s/\$USERNAME/$USER/")
    # now we can get the full path
    projectFile=$(realpath $linkFileLocation/$projectFile)
    echo -e "\033[1;32mProject file: $projectFile\033[0m"
    projectDir=$(dirname $projectFile)

    if [ -d $projectsDir ]; then
        # cd to the projects directory
        cd $projectDir
	echo -e "\033[1;32mChanged directory to: $projectDir\033[0m"
        # Try to read the current project name from the project file. 
        # This might be one of two formats, depending on if we're .xml or .oi
        if [[ $projectFile == *".xml" ]]; then
            currentProjectName=$(grep -oPm1 "(?<=<PROJECT_NAME>)[^<]+" $projectFile)
        elif [[ $projectFile == *".oi" ]]; then
            currentProjectName=$(grep -oPm1 "(?<=PROJECT_NAME = ).*(?=;)" $projectFile)
        fi
        echo -e "\033[1;32mCurrent project: $currentProjectName\033[0m"
    else
        echo -e "\033[1;31mLink file not found at: $linkFilePath\033[0m"
    fi
else
    echo -e "\033[1;31mCurrentProject.xml does not exist at: $currentProjectXml\033[0m"
fi

echo "If you ran this script using 'source' or '. ./scripts/cd_to_data.sh', you can return to the original directory by running 'cd \$LASTDIR'"

export LASTDIR="$LASTDIR"

