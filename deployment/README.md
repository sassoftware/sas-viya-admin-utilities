# Deployment Utilities

## Overview
This directory contains a set of utility scripts designed to assist with Viya deployment management related tasks.

### Supported Functions

#### Manifest ####
Provides utility scripts related to the Viya manifest (site.yaml):

* [splitSiteManifest.sh](manifest/splitSiteManifest.sh): used to split the contents of a site.yaml manifest into two separate files; one that contains all cluster level resources and can be applied by a cluster admin, and another for all all namespace level resources.

#### Roles ####
Provides scripts related to Role and ClusterRole resources:

* [createSASAdminClusterRole.sh](roles/createSASAdminClusterRole.sh): Creates a ClusterRole definition file used for enabling the proper set of cluster-wide permissions required for a Viya administrator.

## Initial Setup

1. These scripts rely on third-party tools `jq` and `yq`. These must be installed and located in your PATH.

## Usage

The scripts accept several command-line arguments to configure its behavior. Below is the set of arguments common to all scripts.

* --help = prints usage information specific to each script
