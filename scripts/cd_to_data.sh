# OI loads projects using a link file in the repository.
linkFileName='CurrentProject.xml'
linkFileLocation=$(realpath $thisScriptDir/../output/)
linkFilePath=$linkFileLocation$linkFileName

# Get the path of the cwd and this script
originalPath=$(pwd)
thisScriptDir=$(dirname $0)
echo "originalPath: $originalPath"
echo "thisScriptDir: $thisScriptDir"

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
    if [ -f $projectFile ]; then
        # get the directory of the project file
        projectsDir=$(dirname $projectFile)
        # cd to the projects directory
        cd $projectDir
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

# Read the data path

export originalPath