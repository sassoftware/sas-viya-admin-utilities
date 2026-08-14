#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname" ; pwd `
thisScript=`basename "$0"`

#############################################################################
function showHelp {
    echo ""
    echo "This script will create a clusterrole definition file for a SAS Admin based on the input permissions file"
    echo ""
    echo "Parameters:"
    echo ""
    echo "-a|--aggregate-role = (optional) The output file containing the generated aggregate role definition"
    echo "-i|--input  = The input permissions csv file"
    echo "-o|--output = the output file containing the generated SAS admin role definition"
    echo "-a|--aggregate-role = (optional) The output file containing the generated aggregate role definition"
    echo "-e|--expand-sas = (optional) Expand the SAS provided api groups details"
    echo "-n|--no-exec = (optional) Flag and omit any records that include pods/exec as the resource"
    echo "-r|--exclude-rules = (optional) A file containing a row per apigroup/resource/verb that should be excluded from the output"
    echo "                    The format of this file matches the input permissions file, except there can be at most 1 apigroup, 1 resource, 1 verb specified per row"
    echo "                    The default is to not exclude any rules."
    echo "-l|--label = (optional) A string representing the name of the new admin role to be created"

}

function buildList {

   IFS=$'|' array=($string)
   numParts=${#array[@]}

returnedString=""
# echo numParts=$numParts
for (( i=0; i<$numParts; i++ ))
do

   part=${array[$i]}
   if [[ "$part" != "" ]]
   then
      if [[ "$part" == "all" ]]
      then
         part="*"
      fi

      if [[ "$returnedString" == "" ]]
      then
         returnedString="[ \"$part\""
      else
         returnedString="$returnedString, \"$part\""
      fi
   fi
done

if [[ "$returnedString" != "" ]]
then
   returnedString="$returnedString ]"
fi

# echo "returnedString: $returnedString"

}

#############################################################################
function writeCSVRecord {

   echo "\"$saveAPIGroup\",\"$saveResourceNames\",\"$saveResources\",\"$saveVerbs\"" >> "$writeFile"

   saveAPIGroup="$apiGroups"
   saveResources="$resources"
   saveResourceNames="$resourceNames"
   if [[ "$verbs" == *'*'* ]]
   then
      saveVerbs="all"
   else
      saveVerbs="$verbs"
   fi

}

#############################################################################
function writeRecord {

  if [[ "$expandSAS" == "0" ]]
  then
     isSASGroup=${sasgroups["$saveAPIGroup"]}

     if [[ "$isSASGroup" == "" ]]
     then
        processRecord="1"
     else
        processRecord="0"
     fi
  else
     processRecord="1"
  fi

  if [[ "$noExec" == "1" && "$saveResources" == *"pods/exec"* ]]
  then
     echo "Found pods/exec, skipping..."
     echo "resources=$saveResources, verbs=$saveVerbs"

     processRecord="0"
  fi

  if [[ "$processRecord" == "1" ]]
  then

	  #  Through the processing so far, we used the apigroup=default to 
	  #  represent the main apigroup in kubernetes.
	  #  However, when building the rules, you need to use what it is truly
	  #  known as is, which is ""

	  if [[ "$saveAPIGroup" == "default" ]]
	  then
	     saveAPIGroup=""
	  fi

	  echo "- apiGroups: [\"$saveAPIGroup\"]" >> "$writeFile"

	  #   Loop over the set of resources and create a valid output line

          #  Through the processing so far, we used the resourceNames=all to 
          #  represent the rules are for all named resources of the resources types.
          #  However, when building the rules, we don't want to include any 
          #  resourceNames line if its for all.
	  if [[ "$saveResourceNames" == "all" ]]
	  then
	     saveResourceNames=""

          else

		  string="$saveResourceNames"
		  buildList
		  echo "  resourceNames: $returnedString" >> "$writeFile"
          fi

	  string="$saveResources"
	  buildList
	  echo "  resources: $returnedString" >> "$writeFile"
	  string="$saveVerbs"
	  buildList
	  echo "  verbs:     $returnedString" >> "$writeFile"

  fi

  saveAPIGroup="$apiGroups"
  saveResourceNames="$resourceNames"
  saveResources="$resources"
  saveVerbs="$verbs"

}

#############################################################################
function collapseResources {

#  We want to collapse the different permissions for each apigroup/resource into 1 superset
#  for that combination.

saveAPIGroup=""
saveResources=""
saveResourceNames=""
saveVerbs=""
writeFile="$collapsedResourceFile"

while IFS='"' read -r delim1 roleName delim3 apiGroups delim4 resourceNames delim5 resources delim6 verbs delim7; do


   #  If first time through, just save the values

   if [[ "$saveAPIGroup" == "" ]]
   then
      saveAPIGroup="$apiGroups"
      saveResourceNames="$resourceNames"
      saveResources="$resources"
      saveVerbs="$verbs"
   else
      #  If new API Group, write out saved values

      if [[ "$saveAPIGroup" != "$apiGroups" ]]
      then
         writeCSVRecord
      else
         # Same set of Resources

         if [[ "$saveResources" == "$resources" && "$saveResourceNames" == "$resourceNames" ]]
         then

            #  Loop over the list of verbs and add the ones we haven't seen yet to the saved
            #  list.
            #  NOTE:  If the saved list is *, don't bother, it's already covered.

            if [[ "$saveVerbs" == *'*'* || "$saveVerbs" == "all" || "$verbs" == *'*'* ]]
            then
               saveVerbs="all"
            else
               saveVerbs="$saveVerbs|$verbs"
               #  Now sort unique to get rid of duplicates
               saveVerbs=`echo "$saveVerbs" | tr '|' '\n' | sort -u | tr '\n' '|'`
            fi

         else
            writeCSVRecord

         fi

      fi

   fi

done < "$uniqueFile"

if [[ "$saveAPIGroup" != "" ]]
then
   writeCSVRecord
fi

}

#############################################################################
function collapseAPIGroups {

#  NOTE:  The input file to this step no longer contains the first column, the rolename.
#         Since we collapsed by resource, the role names are no longer relevant.
#
#  Since the rules are based on the api group, the resourcename and the set of verbs that are the same
#  sort again by just these fields

sort -k 1 -k 2 -k 4 -t ',' -o "$sortFile" "$collapsedResourceFile"


first="1"
saveAPIGroup=""
saveResourceNames=""
saveResources=""
saveVerbs=""

writeFile="$outFile"

while IFS='"' read -r delim1 apiGroups delim4 resourceNames delim5 resources delim6 verbs delim7; do

   #  If first time through, just save the values

   if [[ "$saveAPIGroup" == "" ]]
   then
      saveAPIGroup="$apiGroups"
      saveResourceNames="$resourceNames"
      saveResources="$resources"
      saveVerbs="$verbs"
   else
      #  If new API Group, write out saved values

      if [[ "$saveAPIGroup" != "$apiGroups" ]]
      then
         writeRecord
      else
         # Same set of verbs?
         if [[ "$saveVerbs" == "$verbs" ]]
         then
            #saveResourceNames="$saveResourceNames|$resourceNames"
            saveResources="$saveResources|$resources"
         else
            writeRecord
         fi

      fi

   fi

done < "$sortFile"

if [[ "$saveAPIGroup" != "" ]]
then
   writeRecord
fi

}

#############################################################################
function processExcludes {

   if [[ "$excludeRules" != "" ]]
   then

       excludeWorkFile="rules-minus-excludes-work.csv"

       if [[ -f "$excludeWorkFile" ]]
       then
          rm -f "$excludeWorkFile"
       fi
       excludeOutputFile="rules-minus-excludes.csv"
       if [[ -f "$excludeOutputFile" ]]
       then
          rm -f "$excludeOutputFile"
       fi

#       echo "TEMP: expand verb list for process Excludes to $excludeWorkFile"
#       cp "$uniqueFile" "$excludeOutputFile"

       #  Since the exclude rules are created 1 row per apigroup/resource/verb, we have
       #  to generate a temporary file that has the same syntax (the input file to this
       #  process has verbs collapsed into a single record).

       while IFS='"' read -r delim1 roleName delim3 apiGroups delim4 resourceNames delim5 resources delim6 verbs delim7; do

                    IFS=$'|' verbList=($verbs)

                    numVerbs=${#verbList[@]}
#                    echo "numVerbs=$numVerbs"

                    for (( k=0; k<$numVerbs; k++ ))
                    do

                       verb=${verbList[$k]}

                       echo "\"$roleName\",\"$apiGroups\",\"$resourceNames\",\"$resources\",\"$verb\"" >> "$excludeWorkFile"
                    done

       done < "$uniqueFile"
  
   fi
}

#############################################################################
#  Main
#############################################################################
expandSAS="0"
noExec="0"
excludeRules=""

aggregateRoleFile=""
defaultRoleName="sas-admin-role"
roleName=""

###  Parse the arguments

while [[ $# -gt 0 ]]; do
  case $1 in
     -a|--aggregate-role)
      aggregateRoleFile="$2"
      shift # past argument
      shift # past value
      ;;
     -o|--output)
      outFile="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--input)
      inputFile="$2"
      shift # past argument
      shift # past value
      ;;
     -l|--label)
      roleName="$2"
      shift # past argument
      shift # past value
      ;;
    -e|--expand-sas)
      shift # past argument
      expandSAS="1"
      ;;
    -n|--no-exec)
      shift # past argument
      noExec="1"
      ;;
    -r|--exclude-rules)
#      excludeRules="$2"
      echo "The -r option is not currently fully operational, so is being ignored"
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

if [[ "$inputFile" == "" ]]
then
  echo ""
  echo "ERROR: The name of the input file must be passed as a parameter"
  showHelp
  exit 22
else
  if [[ ! -f "$inputFile" ]]
  then
     echo ""
     echo "ERROR: The inputfile specified does not exist"
     showHelp
     exit 22
  fi
fi

if [[ "$excludeRules" != "" ]]
then
  if [[ ! -f "$excludeRules" ]]
  then
     echo ""
     echo "ERROR: The exclude rules file specified does not exist"
     showHelp
     exit 22
  fi
fi

timestamp=`date +%Y%m%d%H%M%S%N`

#  If we are asked to use an aggregate role definition, then the aggregate role will have the
#  sas-admin-role name and the one that we are specifically generating will have a unique name
#  (using the cadence as part of the identifier)
#  

if [[ "$aggregateRoleFile" != "" ]]
then

   aggregateRoleName="$defaultRoleName"

   if [[ "$roleName" == "" ]]
   then

      roleName="sas-aggregated-${timestamp}"
   fi

   clusterRoleName="$roleName"

else
   aggregateRoleName=""
   clusterRoleName="$defaultRoleName"
fi

echo "Creating output file $outFile"

echo "kind: ClusterRole" > "$outFile"
echo "apiVersion: rbac.authorization.k8s.io/v1" >> "$outFile"
echo "metadata:" >> "$outFile"

echo "  name: $clusterRoleName" >> "$outFile"

#  These metadata annotations and labels help support if aggregate cluster roles are in use

echo "  annotations:" >> "$outFile"
echo "    rbac.authorization.kubernetes.io/autoupdate: \"true\"" >> "$outFile"
echo "  labels:" >> "$outFile"
echo "    sas.com/aggregate-to-namespace-admin: \"true\"" >> "$outFile"

echo "rules:" >> "$outFile"

#  If we are collapsing the SAS provided api groups, add them now
#

#  As of 2022.11, redis is introduced, so add that to the list of SAS groups

#declare -A sasgroups=([viya.sas.com]=viya.sas.com [crunchydata.com]=crunchydata.com [iot.sas.com]=iot.sas.com [opendistro.sas.com]=opendistro.sas.com [webinfdsvr.sas.com]=webinfdsvr.sas.com)
declare -A sasgroups=([viya.sas.com]=viya.sas.com [crunchydata.com]=crunchydata.com [iot.sas.com]=iot.sas.com [opendistro.sas.com]=opendistro.sas.com [webinfdsvr.sas.com]=webinfdsvr.sas.com [redis.kun]=redis.kun)

if [[ "$expandSAS" == "0" ]]
then
   for group in "${sasgroups[@]}"
   do
      echo "- apiGroups: [\"$group\"]" >> "$outFile"

      echo "  resources: [\"*\"]" >> "$outFile"
      echo "  verbs:     [\"*\"]" >> "$outFile"

   done

fi

#
#  We want to generate the fewest amount of rules that cover our needs as possible
#
#  For each one we do define, it needs to generate a stanza that looks like this:
#
#- apiGroups: ["crunchydata.com"]
#  resourceNames: 
#  resources: ["*"]
#  verbs: ["*"]
#
#

uniqueFile="/tmp/permissions-unique-${timestamp}.csv"
sortFile="/tmp/permissions-unique-sort-${timestamp}.csv"
collapsedResourceFile="/tmp/permissions-resource-collapsed-${timestamp}.csv"

#  Sort it in an attempt to put items for the same api group, resource Name, resource and then verbs
#  in successive rows.
#  Also, remove any duplicate records 
#  NOTE: we still may end up where some records have a verb set that is a superset of 
#  others for the same resource
#  Since the rules are based on the api group and the set of verbs that are the same
#  sort again by just these fields

sort -k 2 -k 3 -k 4 -k 5 -t ',' -u -o "$uniqueFile" "$inputFile"

processExcludes

#  We want to collapse the different permissions for each apigroup/resource into 1 superset
#  for that combination.
collapseResources

#  Since the rules are based on the api group and the set of verbs that are the same
#  collapse to that grouping

collapseAPIGroups

if [[ -f "$uniqueFile" ]]
then
   rm "$uniqueFile"
fi
if [[ -f "$sortFile" ]]
then
   rm "$sortFile"
fi

if [[ -f "$collapsedResourceFile" ]]
then
   rm "$collapsedResourceFile"
fi


if [[ "$aggregateRoleFile" != "" ]]
then

echo "Creating aggregate ClusterRole output file $aggregateRoleFile"

echo "apiVersion: rbac.authorization.k8s.io/v1" > "$aggregateRoleFile"
echo "kind: ClusterRole" >> "$aggregateRoleFile"
echo "metadata:" >> "$aggregateRoleFile"
echo "  name: $aggregateRoleName" >> "$aggregateRoleFile"
echo "aggregationRule:" >> "$aggregateRoleFile"
echo "  clusterRoleSelectors:" >> "$aggregateRoleFile"
echo "  - matchLabels:" >> "$aggregateRoleFile"
echo "      sas.com/aggregate-to-namespace-admin: \"true\"" >> "$aggregateRoleFile"
echo "rules: [] # rules are automatically filled in by controller manager" >> "$aggregateRoleFile"

fi

