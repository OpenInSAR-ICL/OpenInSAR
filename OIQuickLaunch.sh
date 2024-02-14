thisPath=$(realpath $(dirname $0))
echo $thisPath
echo ${BASH_SOURCE[0]}
callingPath=$(realpath $PWD)
echo $callingPath
cd $callingPath
bash ~/OpenInSAR/output/ICL_HPC/LAUNCHER.sh $1
