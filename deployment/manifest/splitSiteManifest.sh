#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname" ; pwd `
thisScript=`basename "$0"`

#############################################################################
function showHelp {
    echo ""
    echo "This script will create a cluster admin and a separate namespace admin yaml file from the input site.yaml"
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
    -*|--*)
      echo "ERROR: Invalid parameter, $1"
      exit 22
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
else
  if [[ ! -f "$inputSite" ]]
  then
     echo ""
     echo "ERROR: The input site yaml file specified does not exist"
     showHelp
     exit 22
  fi
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

#  This program will use yq to parse the yaml file on occasion.  Make sure that it resolves.

yqExists=`which yq 2>&1 | grep -v "no yq"`

if [[ "$yqExists" == "" ]]
then
   echo ""
   echo "ERROR: The yq executable is required by this script and must be on the PATH to execute."
   echo "       No yq executable found."
   exit 22
fi

timestamp=`date +%Y%m%d%H%M%S%N`

#  Build the cluster admin file
echo "Creating cluster admin file $outputCluster"

yq eval 'select(.metadata.labels."sas.com/admin" == "cluster-api")' "$inputSite" > "$outputCluster"

#  If there are any extra objects included in the site yaml that need to be put in the cluster admin site yaml, 
#  mark them with a special label that will include them now.
#  Make sure they don't also have any of the other labels that would cause them to be duplicated!

if [[ "$insertInternal" == "1" ]]
then
	echo "---" >> "$outputCluster"
	yq eval 'select(.metadata.labels."sas.com/admin" == "cluster-admin-internal")' "$inputSite" >> "$outputCluster"
fi

if [[ "$includeExecCluster" == "1" ]]
then
   echo "Adding any roles that have pods/exec to $outputCluster"

	echo "---" >> "$outputCluster"
	yq eval 'select(.kind == "Role" and .metadata.name == "pgo-role")' "$inputSite" >> "$outputCluster"
	echo "---" >> "$outputCluster"
	yq eval 'select(.kind == "Role" and .metadata.name == "pgo-target-role")' "$inputSite" >> "$outputCluster"
	echo "---" >> "$outputCluster"
fi

if [[ "$addLabels" == "1" ]]
then

   tmpFile="/tmp/site-cluster-admin-${timestamp}.yaml"

   mv "$outputCluster" $tmpFile

   "$thispath/addLabels/addSplitLabels.sh" -c "$tmpFile" -oc "$outputCluster" 
   
   rm -f $tmpFile

fi

#  Build the namespace admin file

echo "Creating namespace admin file $outputNamespace"

yq eval 'select(.metadata.labels."sas.com/admin" == "cluster-wide")' "$inputSite" > "$outputNamespace"
echo "---" >> "$outputNamespace"

if [[ "$insertInternal" == "0" ]]
then
	yq eval 'select(.metadata.labels."sas.com/admin" == "cluster-admin-internal")' "$inputSite" >> "$outputNamespace"
	echo "---" >> "$outputNamespace"
fi

yq eval 'select(.metadata.labels."sas.com/admin" == "cluster-local")' "$inputSite" >> "$outputNamespace"
echo "---" >> "$outputNamespace"
yq eval 'select(.metadata.labels."sas.com/admin" == "namespace")' "$inputSite" >> "$outputNamespace"
echo "---" >> "$outputNamespace"

#  If we are to put the pods/exec roles in the cluster admin site, we need to remove them from 
#  the namespace site yaml.  
#  I couldn't figure out a reliable way to do this with yq, so back to kustomize
#

if [[ "$includeExecCluster" == "1" ]]
then

   echo "Removing any roles that have pods/exec from $outputNamespace"

   workArea="/tmp/buildAdmin-workarea-${timestamp}"

   mkdir "$workArea"

   cp $thispath/kustomizations/* "$workArea"

   #  Copy the file to update

   nsFilename=`basename "$outputNamespace"`

   cp "$outputNamespace" "$workArea/in-site.yaml"

   #  Replace the namespace in the kustomization files

   pushd "$workArea" > /dev/null
   #  Replace the namespace in the kustomization files

   namespace=`grep "namespace:" in-site.yaml | head -1 | cut -d' ' -f4`

   find . -name '*.yaml' | xargs -l sed -i "s/\${NAMESPACE}/$namespace/g" 

   kustomize build . > "$nsFilename" 

   #  The kustomization that removes the objects leaves empty objects in it, so
   #  remove those now or kubectl apply will fail

   sed -i "/^{}/d" "$nsFilename"
   
   popd > /dev/null

   #  Now replace the output namespace admin file with the updated one

   cp -f "$workArea/$nsFilename" "$outputNamespace"

   rm -r "$workArea"

fi

if [[ "$addLabels" == "1" ]]
then

   tmpFile="/tmp/site-namespace-admin-${timestamp}.yaml"

   mv "$outputNamespace" $tmpFile

   "$thispath/addLabels/addSplitLabels.sh" -n "$tmpFile" -on "$outputNamespace"

   rm -f $tmpFile

fi

