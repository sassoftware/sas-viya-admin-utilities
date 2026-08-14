# Usage Analysis Utilities

## Overview
This directory contains a set of scripts designed to provide insights into usage and activity within a Viya environment.

### Supported Domains

| Scenario         | Description                                 |
|------------------|---------------------------------------------|
| Compute          | Provides insights into compute server activity
| Content          | Provides insights into the various content resources persisted and used by Viya services and applications
| Users            | Provides insights into user activity, including session logons/logoffs

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
