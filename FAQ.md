# FAQ

- #### What does the '.oi' Project File do?
  This file defines working directories, paths, and key parameters such that all workers launched on the HPC know what to do and where to do it.
  The software will automatically create these directories if these do not exist.

- #### What are '\$HERE\$', '\$PROJECT_NAME\$', and '\$HOME\$' in the Project Files?
  These are placeholders for variables that will be stored by the software and replaced with their values at runtime.
  - '\$HERE\$' : the location of the Project File.
  - '\$PROJECT_NAME\$' : the PROJECT_NAME variable defined in the Project File.
  - '\$HOME\$' : the user's home directory.
