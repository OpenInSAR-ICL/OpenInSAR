# OpenInSAR_internal

This is a guide for using the 'old style' Matlab scripts on Imperial HPC

---
#### 1. Clone the repository

  The latest patches will generally be on the 'dev' branch.

  > mkdir WHATEVER_YOU_WANT_TO_CALL_THE_CODE_REPOSITORY
  > 
  > cd WHATEVER_YOU_WANT_TO_CALL_THE_CODE_REPOSITORY
  > 
  > git clone https://github.com/OpenInSAR-ICL/OpenInSAR.git .
  >
  > git pull origin dev
  
  Note the . at the end. You can leave off the '.', and then it will clone to a directory called OpenInSAR.
  
---
#### 2. Checkout the 'dev' branch and pull the latest updates
  
  > git fetch
  >
  > git pull origin dev

---
#### 3. Edit prototype/secrets.txt
  > nano ~/secrets.txt
  
  add your Alaska Satellite Facility / NASA EarthData credentials (these are currently the same thing)
  
  > AsfUsername=YOUR_ASF_USERNAME
  > 
  > AsfPassword=YOUR_ASF_PASSWORD
  >
  > NasaUsername=YOUR_ASF_USERNAME
  >
  > NasaPassword=YOUR_ASF_PASSWORD

---

#### 4. Edit the OpenInSAR configuration to fit your area
  Start by copying an example 'Project File' to a new file called 'MyProject.oi'.
  Copy this file to ephemeral storage, as the data will be generated relative to the location of this Project File
  
  Assuming we are in this repository:
  
  > cp output/+OI/Examples/ExampleProject_template.oi ~/../projects/insardatastore/ephemeral/YOUR_COLLEGE_USERNAME/MyProject.oi
  >
  > nano ~/../projects/insardatastore/ephemeral/YOUR_COLLEGE_USERNAME/MyProject.oi
  
  If you call the file anything other than 'MyProject.oi' or if you move it to somewhere other than the above, you will have to edit 'output/CurrentProject.xml' in order to update the location to reflect your Project File location.

---

#### 5. Add permissions to the launcher script, run it
  
  
  > \# assuming you are in the cloned repository
  >
  > cd output
  >
  > chmod +x ICL_HPC/LAUNCHER.sh
  > 
  > ./ICL_HPC/LAUNCHER.sh 99

---

#### 6. Check the workers are running/queued
  To check queue status:
  
  > qstat
  
  If there are issues getting workers starting, you can check the [HPC status](https://status.rcs.imperial.ac.uk/) in terms of queue times and maintainance (requires VPN connection).
  
  Workers will log their status and recieve jobs in their corresponding W#.worker file (where # is the worker index [1..99]) in the 'postings' subdirectory in the Project directory.
  
  > cat W2.worker
  > 
  > \# should say something like 'READY', or 'Running Job X'

---

#### 7. Start a leader
  Once the workers are running, a folder will be created here:
  
  > ~/../projects/insardatastore/ephemeral/YOUR_COLLEGE_USERNAME/WHATEVER_YOU_CALLED_THE_PROJECT/postings/
  
  One of the workers is 'interactive' in that we can write Matlab commands in 'interactive_input.txt' and the results will be written in 'interactive_output.txt'.
  Hence we can nominate the worker to be the leader by simply writing 'leader' in the 'interactive_input.txt' file
  
  > echo "leader" > interactive_input.txt
  
  When a command has been receieved from the interactive_input.txt file, the file will be cleared by the worker/leader.
  You can now see what the leader is doing via:
  
  > cat interactive_output.txt

---

#### 7.B [OPTION B] Launch Matlab on your own machine.
  This requires access to the RDS.
  In Matlab:
  
  > addpath('ICL_HPC')
  >
  > leader
  
  Make sure ICL_HPC/leader.m is loading the correct .oi file, and that ICL_LEADER/worker.m is too.

---

#### 7.C [OPTION C] Launch an interactive session
  > qsub interactive.pbs
  
  Wait for it to load, then start Matlab
  
  > cd LOCATION_OF_THIS_REPOSITORY
  > 
  > ./output/ICL_HPC/leader.sh
  
  I think the HPC is having trouble with interactive sessions at the moment.

---

#### 8 Let me know any issues
  Note that there is an issue with files not updating on the Research Data Store which we can't do anything about, so this 'old' approach is very buggy.
  Results should be generated in 
  > ~/../projects/insardatastore/ephemeral/YOUR_COLLEGE_USERNAME/

