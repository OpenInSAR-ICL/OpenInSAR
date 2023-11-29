# OpenInSAR_internal
mv ~/../projects/insardatastore/ephemeral/PAT ~/PAT.txt I will be working to 
make this easier, but in the meantime...
#### 1. Note your github username and get a github personal access token (PAT)
https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens 
copy this somewhere safe
#### 2. save the PAT in your home dir
> cd ~
> 
> nano GithubPAT.txt
paste PAT contents into the editor and save
#### 3. Go to your ephemeral storage
cd ~/../ephemeral
#### 4. Load the PAT into a variable
> GithubPAT=$(<~/GithubPAT.txt)
do the same for your username
> MyUsername=insar-uk
#### 5. Clone the repository
>git clone 
>https://$MyUsername:$GithubPAT@github.com/insar-uk/OpenInSAR_internal.git
#### 6. Edit prototype/secrets.txt
> nano ~/../ephemeral/OpenInSAR_internal/prototype/secrets.txt
add your Alaska Satellite Facility / NASA EarthData credentials (these are currently the same thing)
#### 7. Edit the OpenInSAR configuration to fit your area
> nano ~/../ephemeral/OpenInSAR_internal/test_2023_06_21.oi
you will probable need to move this
> cp ~/../ephemeral/OpenInSAR_internal/test_2023_06_21.oi 
> ~/../ephemeral/test_2023_06_21.oi
#### 8. Edit the leader.m and worker.m files to ensure they point to this OpenInSAR configuration file
> nano prototype/leader.m
edit th

#### 8. Add permissions to the launcher script, run it
> chmod +x PBS/LAUNCHER.sh
> 
> ./PBS/LAUNCHER.sh
run old launcher
#### 9. Check the workers are running/queued
> qstat


## Running the leader
#### 10.A Launch Matlab on your host machine.
In matlab:
> addpath('prototype')
> leader
Make sure prototype/leader.m points to the correct .oi file, and that prototype/worker.m matches this.

#### 10.B [OPTION B] Launch an interactive session
> qsub interactive.pbs
Wait for it to load, then start matlab
> cd ~/../ephemeral/OpenInSAR_internal
> chmod +x /PBS/leader.sh
> ./PBS/leader.sh
Make sure prototype/leader.m points to the correct .oi file, and that prototype/worker.m matches this.

#### 12. It should run from here?!


## Check queue status:
> qstat
https://status.rcs.imperial.ac.uk/
