# Ingress Scripts

This folder contains example scripts to be use with Kubernetes Ingress objects.


## convertToMasterMinionIngress.sh

This script will modify an existing site.yaml created by kustomize from a SAS Viya deployment directory. The output is a new site.yaml with the ingress resources split between hosts and identified as minions, and a master resource for each host identified. This approach is required for use with the NGINX+ Ingress Controller.

### Syntax

   convertToMasterMinionIngress.sh [[required-parameters](#required-parameters)] [[optional-parameters](#optional-parameters)]

#### Required Parameters
 **--input, -i**  <ins>file to be used as original definition</ins>

 This should be an absolute or relative path including the filename.

#### Optional Parameters
**--output, -o**  <ins>destination directory for output file</ins>

By default the file will be written to the current directory as "new_site.yaml"

**--namespace, -n**  <ins>the namespace where the ingress resoruces should be created</ins>

By default this will be the namespace found in the first object in the input file.

### Example
    $> ./convertToMasterMinionIngress.sh --input deploy/mycluster/mynamespace/site.yaml --output /home/myhome/ --namespace mynamespace




### See Also

* [NGINX Ingress Controller](https://docs.nginx.com/nginx-ingress-controller)
* [Mergeable Ingress Types Support](https://github.com/nginx/kubernetes-ingress/tree/main/examples/ingress-resources/mergeable-ingress-types)
