# sas-viya-admin-utilities

This project contains utility scripts designed to assist users with administering a Viya environment.

## Getting started

Scripts are provided for the following domains:

| Domain                            | Description                                 |
|-----------------------------------|---------------------------------------------|
| [compute](compute)                | Provides insights into compute server activity, including managing contexts required to launch compute/batch sessions.
| [configuration](configuration)    | Assists with configuring a Viya environment as well as performing administrative tasks.
| [deployment](deployment)          | Manages the configuration files required to deploy Viya.
| [usageAnalysis](usageAnalysis)    | Provides insights into usage and activity within a Viya environment, including information about which users are accessing the environment and when.


## Usage

Scripts contained within this project accept several command-line arguments to configure their behavior. Below is the set of arguments common to all scripts.

* --help = prints usage information specific to each script, along with the list of available options
* -k|--insecure = disables TLS certificate checking
* -o|--output-directory = the directory to write output files to, defaults to the current working directory.

## Contributing
We welcome your contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details about submitting contributions to this project.

## License
This project (including historical versions) is licensed under the [Apache 2.0 License](LICENSE).