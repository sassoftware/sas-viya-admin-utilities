#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname" ; pwd `
thisScript=`basename "$0"`

timestamp=`date +%Y%m%d%H%M%S%N`

#############################################################################
function showHelp {
    echo ""
    echo "This script will apply common labels to the namespace or cluster site yaml file"
    echo ""
    echo "Parameters:"
    echo ""
    echo "-n|--input-namespace-yaml  = The input namespace site yaml"
    echo "-on|--output-namespace-yaml = the output file containing the namespace admin yaml file with the added labels"
    echo "-c|--input-cluster-namespace = The input cluster site yaml"
    echo "-oc|--output-cluster-namespace = the output file containing the cluster admin yaml file with the added labels"

}

#############################################################################
#  Main
#############################################################################
inputNamespaceSite=""
inputClusterSite=""
outputCluster=""
outputNamespace=""

###  Parse the arguments

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--input-cluster-yaml)
      inputClusterSite="$2"
      shift # past argument
      shift # past value
      ;;
    -oc|--output-cluster-yaml)
      outputCluster="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--input-namespace-yaml)
      inputNamespaceSite="$2"
      shift # past argument
      shift # past value
      ;;
    -on|--output-namespace-yaml)
      outputNamespace="$2"
      shift # past argument
      shift # past value
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

if [[ "$inputNamespaceSite" == "" && "$inputClusterSite" == "" ]]
then
  echo ""
  echo "ERROR: One of the namespace yaml or cluster yaml file must be passed as a parameter"
  showHelp
  exit 22
fi

if [[ "$inputNamespaceSite" != "" ]]
then
        if [[ ! -f "$inputNamespaceSite" ]]
        then
             echo ""
             echo "ERROR: The input namespace yaml file specified does not exist"
             showHelp
             exit 22
          fi

        if [[ "$outputNamespace" == "" ]]
        then
          echo ""
          echo "ERROR: The name of the file to contain the output namespace yaml must be passed as a parameter"
          showHelp
          exit 22
        fi

        #
        #  Now build the new version of the namespace file
        #

        tmpDir="/tmp/namespace-label-${timestamp}"

        mkdir "$tmpDir"

        cp $thispath/namespace/* $tmpDir

        echo "Using input namespace file $inputNamespaceSite"
        cp $inputNamespaceSite $tmpDir/site-namespace-admin.yaml

        pushd $tmpDir > /dev/null

        kustomize build . -o site-namespace-admin-labelled.yaml
        rc=$?

        popd > /dev/null

        if [[ "$rc" == "0" ]]
        then
           echo "Created output namespace file $outputNamespace"
           cp $tmpDir/site-namespace-admin-labelled.yaml $outputNamespace
        else
           echo "ERROR: Applying label failed with rc=$rc, output file $outputNamespace not created."
        fi

        rm -rf $tmpDir

fi

if [[ "$inputClusterSite" != "" ]]
then
	if [[ ! -f "$inputClusterSite" ]]
	then
	     echo ""
	     echo "ERROR: The input cluster yaml file specified does not exist"
	     showHelp
	     exit 22
	  fi

	if [[ "$outputCluster" == "" ]]
	then
	  echo ""
	  echo "ERROR: The name of the file to contain the output cluster yaml must be passed as a parameter"
	  showHelp
	  exit 22
	fi

        #
        #  Now build the new version of the namespace file
        #

        tmpDir="/tmp/cluster-label-${timestamp}"

        mkdir "$tmpDir"

        cp $thispath/cluster/* $tmpDir

        echo "Using input cluster file $inputClusterSite"
        cp $inputClusterSite $tmpDir/site-cluster-admin.yaml

        pushd $tmpDir > /dev/null

        kustomize build . -o site-cluster-admin-labelled.yaml
        rc=$?

        popd > /dev/null

        if [[ "$rc" == "0" ]]
        then
           echo "Created output cluster file $outputCluster"
           cp $tmpDir/site-cluster-admin-labelled.yaml $outputCluster
        else
           echo "ERROR: Applying label failed with rc=$rc, output file $outputCluster not created."
        fi

        rm -rf $tmpDir

fi

