# OpenInSAR_internal

This is a guide for using the 'old style' Matlab scripts on Imperial HPC

---
#### 1. Clone the repository (use the 'dev' branch)

  The latest patches are generally on the 'dev' branch.

  For now we will assume that your folder is in 'Home' on the HPC. ('~')

  To navigate to home if you've been doing other things, just enter:

  > cd ~

  Let's assume your new OpenInSAR folder will be called my_openinsar. Let's create it and download the scripts.

  > mkdir my_openinsar
  > 
  > cd my_openinsar
  > 
  > git clone -b dev https://github.com/OpenInSAR-ICL/OpenInSAR.git .

  
  Note the . at the end. If you leave off the '.', then it will clone to a directory called OpenInSAR.
  
---
#### 2. Update
  
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
  Start by copying an example 'Project File' to a new file called 'CurrentProject.oi'.

  Copy this file to YOUR PERSONAL ephemeral storage, as the data will be generated relative to the location of this Project File
  
  Assuming we are in this repository:
  
  > cp output/+OI/Examples/ExampleProject_template.oi ~/../ephemeral/CurrentProject.oi
  >
  > nano ~/../ephemeral/CurrentProject.oi
  
  If you call the file anything other than 'CurrentProject.oi' or if you move it to somewhere other than the above, you will have to also edit 'output/CurrentProject.xml' in order to update the location to reflect your Project File location.

---

#### 5. Make a launch script

As we are probably running more than one processing project, it's convenient to create a script to launch the HPC workers.

```
cd ~
nano ~/LAUNCH
```

Copy and paste this:
```
thisPath=$(realpath $(dirname $0))
callingPath=$(realpath $PWD)
bash ~/my_openinsar/output/ICL_HPC/LAUNCHER.sh $1
```

Note that '~/my_openinsar/' should be edited if you named your software folder something else or moved it.

Now tell the HPC that we are happy to run the new script:

> chmod +x ~/LAUNCH

And we can run it like so:

> bash ~/LAUNCH

Which will launch 99 workers by default. They will look for '~/../ephemeral/CurrentProject.oi' by default, and run the project defined there. To change which default project, edit './output/CurrentProject.xml'

#### 6. Check the workers are running/queued
  To check queue status:
  
  > qstat
  
  If there are issues getting workers starting, you can check the [HPC status](https://status.rcs.imperial.ac.uk/) in terms of queue times and maintainance (requires VPN connection).
  
  Workers will log their status and recieve jobs in their corresponding W#.worker file (where # is the worker index [1..99]) in the 'postings' subdirectory in the Project directory.
  ```
  cd postings
  cat W2.worker
  \# should say something like 'READY', or 'Running Job X'
  ```
---

If everything is running well, we should have results in a couple of hours!

#### Let me know any issues!
  Note that there is an issue with files not updating on the Research Data Store which we can't do anything about, so this 'old' approach is very buggy.
  Results should be generated in 
  > ~/../ephemeral/MY_PROJECT/
 


