#  Context Directory 

This directory contains the file and directory structure needed to be passed to the manageContexts.sh script.

The default contents of this directory contain sample files for:

- creating a [new pod template for use with a compute context](overlays/_sample-compute-pod)
- creating a [new pod template for use with a batch context](overlays/_sample-batch-pod)
- creating a [new launcher context](_sample-compute-launcher.json and _sample-batch-launcher.json)
  - For details on the options and syntax available when creating a new launcher context, generate a template using:
`sas-viya compute launchers gen -f launcher-template.json`
where -f contains the name of the template json to create.
- creating a [new compute context](_sample-compute.json)
  - For details on the options and syntax available when creating a new compute context (in xxxx-compute.json), see the [Compute API Documentation](https://developer.sas.com/apis/rest/Compute/#computeapi).
- creating a [simple new batch context](_sample-batch.csv) or a [standard new batch context](_sample-batch.json).
  - NOTE: The simple (ie. *-batch.csv) mostly exists for backwards compatibility.  It is recommended to use the *-batch.json format instead.

**NOTE:** All files and directories starting with an _ will be skipped by manageContexts.sh.  To create your own content, make sure to name your files and directories such that they do not start with an _.

For samples of what can be specified to accomplish different tasks, see the [samples area](../samples) of the git repo.
