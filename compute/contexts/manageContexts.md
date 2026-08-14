# Details on using manageContexts.sh

## Overview

The [manageContexts.sh](manageContexts.sh) script is used to manage resources related to the SAS compute environment.  These resources include:

- Kubernetes Pod Templates
- SAS Launcher Contexts
- SAS Compute Contexts
- SAS Batch Contexts

For details on what these items are and what they are used for, see the [SAS Viya Administration](https://go.documentation.sas.com/doc/en/sasadmincdc/v_023/calcontexts/n01003viyaprgmsrvs00000admin.htm) documentation. **NOTE:** Make sure to reference the appropriate page for the Viya release you are currently using.

For details on the parameters of this script, see the showHelp function in the [script itself](manageContexts.sh).

For details on the file formats and what each can contain, see the [README file](samples/_initialContextDirectoryContent/README.md) in the context directory.

## Setup

The main input to this script, is a directory of files and folders.  

To initialize a new directory for use as input to this script, one can run the manageContext.sh with the -i option, ex.

`compute/manageContexts.sh -i -d <directory>`

This will create the directory <directory> with the appropriate directory structure with s ls on the file formats and what each can contain, see the [README file](samples/_initialContextDirectoryContent/README.md) in the context directory.

sample files.  

**NOTE:** All of the sample files and directories start with an underscore.  The manageContexts.sh script will skip all files/directories that start with an underscore such that samples are not accidentally added to your system.  To execute the samples, rename the files and directories to remove the leading underscore.

The two main types of actions currently supported are:

1. Create Pod Templates 
2. Create Contexts 

When executing the script with either no action options specified, or the --all option, the script will execute the appropriate actions based on the content in the directory.

However, there may be times when you want to execute the steps separately.  For example, pod templates require Kubernetes permissions and may be added less frequently.  Thus, you can execute with the -t option only which will only create the pod templates.  Similarly, creating contexts require SAS administrative permissions and may be done more frequently.  Thus, you can execute with the -c option to only create contexts.

If you are specifying to create Pod Templates, the following pre-requisites exist:

- You must have appropriate permissions on the Kubernetes namespace (specified on the -n option) to add resources
- You must have the kubectl command installed where this script is executing
- You must have the kubeconfig set appropriately to access the cluster through kubectl

If you are specifying to create SAS contexts, the following pre-requisites exist:

- You must have the sas-viya cli installed with a minimum set of plugins of:
  - auth
  - authorization
  - compute
  - batch
- sas-viya command is available on the PATH (ie. can be executed without specifying a full path)
- the jq package is installed and the jq command is available on the PATH (ie. can be executed without specifying a full path)
  - If you need to install jq, more information can be obtained [here](https://stedolan.github.io/jq/download/)
- SAS_CLI_PROFILE environment variable must be set to the sas cli profile name to use
- SSL_CERT_FILE if your cli profile is accessing an https endpoint, this environment variable must contain the ssl certificate file to use
- A valid authentication token must be active for the specified cli profile.  To create a valid token, use `sas-viya auth login`
- The userid used to create the authentication token must have permssions to add contexts

## Execution

To create a new base directory with sample content:

`compute/manageContexts.sh -d <directory> -i`

To execute all actions based on the content of your base directory:

`compute/manageContexts.sh -d <directory> -n <namespace>`

which is equivalent to:

`compute/manageContexts.sh -d <directory> -n <namespace> --all`

To just create the pod templates:

`compute/manageContexts.sh -d <directory> -n <namespace> -t`

To just create the contexts:

`compute/manageContexts.sh -d <directory> -c`
