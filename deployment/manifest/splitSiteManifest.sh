#!/bin/bash

#############################################################################
function showHelp {
    echo ""
    echo "This script will create a cluster admin and a separate namespace admin yaml file from the input site.yaml"
    echo ""
    echo "Cluster-scoped objects (no metadata.namespace) are always put in the cluster admin file, since a"
    echo "namespace admin cannot create them, even when their sas.com/admin label would place them in the namespace file."
    echo ""
    echo "Parameters:"
    echo ""
    echo "-i|--input-site-yaml  = The input site.yaml to use as a starting point"
    echo "-c|--output-cluster = the output file containing the cluster admin yaml file (default=site-cluster-admin.yaml)"
    echo "-n|--output-namespace = the output file containing the namespace admin yaml file (default=site-namespace-admin.yaml)"
    echo "-e|--include-exec = include any roles that need pods/exec into cluster admin yaml"
    echo "-s|--insert-internal = insert internal cluster objects into cluster admin file"
    echo "-l|--skip-label = by default, a label will be added to all objects in the respective files representing which scope/file they came from.  This option will exclude those labels from being added."
}

#############################################################################
#  Main
#############################################################################
inputSite=""
outputCluster="site-cluster-admin.yaml"
outputNamespace="site-namespace-admin.yaml"
includeExecCluster="0"
insertInternal="0"
addLabels="1"
action=""

###  Parse the arguments

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--output-cluster)
      outputCluster="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--output-namespace)
      outputNamespace="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--input-site-yaml)
      inputSite="$2"
      shift # past argument
      shift # past value
      ;;
    -e|--include-exec)
      shift # past argument
      includeExecCluster="1"
      ;;
    -l|--skip-label)
      shift # past argument
      addLabels="0"
      ;;
    -s|--insert-internal)
      insertInternal="1"
      shift # past argument
      ;;
    --help)
      shift # past argument
      action="help"
      ;;
    *)
      echo "ERROR: Invalid parameter, $1"
      exit 22
      ;;
  esac
done

#  Handle some high level actions first

if [[ "$action" == "help" ]]
then
   showHelp
   exit 0
fi

if [[ "$inputSite" == "" ]]
then
  echo ""
  echo "ERROR: The name of the input site yaml file must be passed as a parameter"
  showHelp
  exit 22
elif [[ ! -f "$inputSite" ]]
then
  echo ""
  echo "ERROR: The input site yaml file specified does not exist"
  showHelp
  exit 22
fi

if [[ "$outputCluster" == "" ]]
then
  echo ""
  echo "ERROR: The name of the file to contain the cluster admin yaml must be passed as a parameter"
  showHelp
  exit 22
fi

if [[ "$outputNamespace" == "" ]]
then
  echo ""
  echo "ERROR: The name of the file to contain the namespace admin yaml must be passed as a parameter"
  showHelp
  exit 22
fi

#  Requires mikefarah yq v4 with -c (compact sequence indent, matching kustomize output).

if ! yq -c -n '.' > /dev/null 2>&1
then
   echo ""
   echo "ERROR: mikefarah yq v4 with -c support must be on the PATH."
   exit 22
fi

#  Each output file is built with ONE yq select so documents keep site.yaml's order,
#  which kustomize build has already sorted.  Every condition below is a yq expression.

admin='.metadata.labels."sas.com/admin"'

# Labels applied by SAS's deploy procedure.  Others go to neither file: "none" (build-time
# inputs, one-off migration jobs) and upgrade-only objects that SAS applies by their own procedure.
deployable="($admin == \"cluster-api\" or $admin == \"cluster-admin-internal\" or $admin == \"cluster-wide\" or $admin == \"cluster-local\" or $admin == \"namespace\")"

# No namespace = cluster-scoped (e.g. sas-logon-app's ClusterRoleBinding)
clusterScoped='(.metadata.namespace == null)'

# Roles that grant pods/exec (e.g. postgres-operator)
execRoles='(.kind == "Role" and ([.rules[]?.resources[]?] | any_c(. == "pods/exec")))'

# Objects a namespace admin can't create.  The namespace file gets every other deployable
# object, so the files never overlap and no deployable object is dropped.
needsClusterAdmin="$admin == \"cluster-api\" or $clusterScoped"

if [[ "$insertInternal" == "1" ]]
then
   needsClusterAdmin="$needsClusterAdmin or $admin == \"cluster-admin-internal\""
fi

if [[ "$includeExecCluster" == "1" ]]
then
   needsClusterAdmin="$needsClusterAdmin or $execRoles"
fi

#  yq filter appended to the select: add the scope label, keeping label keys sorted as kustomize did
function scopeLabel {
   if [[ "$addLabels" == "1" ]]
   then
      echo " | .metadata.labels.\"sas.com/admin-scope\" = \"$1\" | .metadata.labels |= sort_keys(.)"
   fi
}

echo "Creating cluster admin file $outputCluster"
yq -c "select($deployable and ($needsClusterAdmin))$(scopeLabel cluster)" "$inputSite" > "$outputCluster" || exit 1

echo "Creating namespace admin file $outputNamespace"
yq -c "select($deployable and (($needsClusterAdmin) | not))$(scopeLabel namespace)" "$inputSite" > "$outputNamespace" || exit 1

#  List what went to neither file, so a new sas.com/admin value in a future release isn't silently dropped
echo "Not in either file (count, sas.com/admin label):"
yq "select(.kind != null and ($deployable | not)) | $admin // \"<unlabelled>\"" "$inputSite" | grep -v '^---$' | sort | uniq -c
