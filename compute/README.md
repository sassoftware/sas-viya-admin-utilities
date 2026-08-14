# Compute Utilities

## Overview
This directory contains a set of utility scripts related to SAS Compute servers.

### Supported Functions

#### Contexts ####
Provides utility scripts related to the management of compute, launcher, and batch contexts:

* [manageContexts.sh](contexts/manageContexts.sh): used to create batch, compute, launcher contexts and new pod templates. The script acccepts a directory of files describing the actions to perform, and the details of the objects to be created and loops over them to create them. For workflow and details, see [here](contexts/manageContexts.md).

* [genGroupContexts.sh](contexts/genGroupContexts.sh): a common way of defining compute objects is by group (ex. department, org, role, etc.).  This script takes in a list of groups, and a template directory describing how to create the compute objects, and creates the folder structure wanted by manageContext.sh which is then used to define the objects.

#### Files ####
Provides utility scripts related to files accessible via a SAS compute server session:

* [downloadFile.sh](files/downloadFile.sh): download files from a location on the SAS Server to your local machine

* [uploadFile.sh](files/uploadFile.sh): upload files to a target location on the SAS Server


## Initial Setup

1. All scripts in this directory require a SAS Viya CLI profile for authentication. Follow the instructions located [here](https://go.documentation.sas.com/doc/en/sasadmincdc/v_056/calcli/n01xwtcatlinzrn1gztsglukb34a.htm) to ensure the SAS Viya CLI is installed and properly configured.

2. After the CLI has been installed, set up one or more profiles to point to the environments you want to connect to.

3. Set the `SAS_CLI_PROFILE` environment variable to match the preferred profile as follows:

    export SAS_CLI_PROFILE=prod

4. Authenticate to that environment:

    sas-viya auth login

5. These scripts rely on third-party tools `jq` and `curl`. These must be installed and located in your PATH.

## Usage

The scripts accept several command-line arguments to configure its behavior. Below is the set of arguments common to all scripts.

* --help = prints usage information specific to each script
* -k|--insecure = disables TLS certificate checking
* -o|--output-directory = the directory to write output files to, defaults to the current working directory.
