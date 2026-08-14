#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname" ; pwd `
thisScript=`basename "$0"`

#############################################################################
function showHelp {
    echo ""
    echo "This script will create a clusterrole definition file for a SAS Admin based on the input site.yaml file"
    echo ""
    echo "Parameters:"
    echo ""
    echo "-i|--input-site-yaml  = The input site.yaml to use as a starting point"
    echo "-o|--output = the output file containing the generated SAS admin role definition (default=sas-admin-clusterrole.yaml in same path as input file)"
    echo "-a|--aggregate-role = (optional) the output file containing the generated aggregate role definition. Note that this option also implies to modify the name and content of the generated cluster role to be consistent with the use of the aggregate role."
    echo "-x|--expand-sas = (optional) expand the sas API groups into their details"
    echo "-v|--expand-verbs = (optional) expand any verb wildcards to its full list"
    echo "-c|--csv-output = (optional) the csv file that the information used to create the output file"
    echo "-e|--no-exec = (optional) flag and omit any pod/exec rules"
    echo "-r|--exclude-rules = (optional) a csv file specifying a row per apigroup/resource/verb that should not be included in the output"
    echo "                     All values in the csv file must be enclosed in quotes \"\""
    echo "                     Default is to include all rules."
    echo "-d|--debug = (optional) turn on additional diagnostic messages"

}

#############################################################################
#  Main
#############################################################################
inputSite=""
outCSV=""
expandSASFlag=""
outFilename="sas-admin-clusterrole.yaml"

execFlag=""
expandVerbFlag=""

excludeRules=""
debug="0"

aggregateRoleFileOption=""

###  Parse the arguments

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--csv-output)
      outCSV="$2"
      shift # past argument
      shift # past value
      ;;
    -a|--aggregate-role)
      aggregateRoleFileOption="-a $2"
      shift # past argument
      shift # past value
      ;;
    -d|--debug)
      shift # past argument
      debug="1"
      ;;
    -o|--output)
      outFile="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--site-yaml)
      inputSite="$2"
      shift # past argument
      shift # past value
      ;;
    -r|--exclude-rules)
      echo "The -r option is not fully functional and is being ignored"
#      excludeRules="-r \"$2\""
      shift # past argument
      shift # past value
      ;;
    -x|--expand-sas)
      shift # past argument
      expandSASFlag="-e"
      ;;
    -v|--expand-verbs)
      shift # past argument
      expandVerbFlag="-x"
      ;;
    -e|--no-exec)
      shift # past argument
      execFlag="-n"
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

#  This program will use yq to parse the yaml file on occasion.  Make sure that it resolves.

yqExists=`which yq 2>&1 | grep -v "no yq"`

if [[ "$yqExists" == "" ]]
then
   echo "ERROR: yq is used to parse the input yaml file and must already be installed in the PATH"
   exit 22
fi
SECONDS=0
timestamp=`date +%Y%m%d%H%M%S%N`

if [[ "$debug" == "1" ]]
then
   echo "$SECONDS: Starting to process request to create cluster role, $timestamp"
fi
rc=0

#   Generate the yq output

if [[ "$debug" == "1" ]]
then
   echo "$SECONDS: Extracting Role information from the site yaml"
fi

rolesYaml="/tmp/permissions-${timestamp}.lst"
rolesCSV="/tmp/permissions-${timestamp}.csv"

yq eval '. | select(.kind == "Role") | [.metadata.name,.rules[]]' "$inputSite" | grep -v "\[\]" > "$rolesYaml"

if [[ "$debug" == "1" ]]
then
   echo "$SECONDS: Finished Extracting Role information from the site yaml"
fi

#   Parse the permissions

if [[ "$debug" == "1" ]]
then
   echo "$SECONDS: Parsing Role information..."
fi
"$thispath/_parseK8sRoles.sh" -i "$rolesYaml" -o "$rolesCSV" $expandVerbFlag 
rc="$?"

if [[ "$debug" == "1" ]]
then
   echo "$SECONDS: Finished parsing Role information..."
fi
if [[ "$rc" == "0" ]]
then
	#   Generate the ClusterRole 

	if [[ "$debug" == "1" ]]
	then
	   echo "$SECONDS: Generating the ClusterRole..."
	fi

        if [[ "$aggregateRoleFileOption" != "" ]]
        then
           #  build a reasonable label for the new cluster role
           #  Get the release information from the input yaml file

           release=`yq -e 'select(.kind == "ConfigMap") | select(.metadata.name == "sas-deployment-metadata*") | .data.SAS_CADENCE_VERSION' "$inputSite"`
echo "Found release: $release"
           #  NOTE: if something happens here and the release information is not found, the returned release value will be "null"
           if [[ "$release" == "null" ]]
           then
              echo "WARNING: SAS Release information not found in input file, $inputSite"
           fi

           roleName="sas-admin-${release}-${timestamp}" 
           roleNameOption="-l ${roleName}"
           outFilename="${roleName}.yaml"
        else
           roleNameOption=""
        fi

        if [[ "$outFile" == "" ]]
        then
           inputPath=`dirname $(realpath "$inputSite")`
           outFile="$inputPath/$outFilename"
        fi

        #echo "Creating output file $outFile"

	"$thispath/_genSASAdminClusterRole.sh" -i "$rolesCSV" -o "$outFile" $aggregateRoleFileOption $roleNameOption $expandSASFlag $execFlag $excludeRules 
	if [[ "$debug" == "1" ]]
	then
	   echo "$SECONDS: Finished generating the ClusterRole..."
	fi

	if [[ "$outCSV" != "" ]]
	then
	   echo "Creating output csv file $outCSV"
	   mv "$rolesCSV" "$outCSV"
	else
	   rm "$rolesCSV"
	fi
else
    echo "ERROR: Failure parsing Role information, stopping"
fi
if [[ "$debug" == "1" ]]
then
   echo "$SECONDS: Finished processing request to create cluster role"
fi

exit $rc
