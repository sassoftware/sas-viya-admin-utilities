# Configuration Utilities

## Overview
This directory contains a set of utility scripts designed to assist with configuration related tasks.

### Supported Functions

#### Identities ####
Provides utility scripts related to the configuration of registered identities:

* [moveUserContent.sh](identities/moveUserContent.sh): moves user content (files stored in a user's home folder within the SAS Content tree) from one user-id to another.
* [updateUserPreferences.sh](identities/updateUserPreferences.sh): updates user based preferences (i.e. settings) for Viya applications
* UID / GID scripts - see the [README](identities/uid/README.md) for details on how to use the uid/gid utility scripts

#### Jobs ####
Provides utility scripts related to the configuration of jobs submitted through the SAS Job Execution service:

* [updateJobExpiration.sh](jobs/updateJobExpiration.sh): updates the expiration time for completed jobs.

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
* --page-size = controls the number of records to include in a single page when communicating with Viya services
