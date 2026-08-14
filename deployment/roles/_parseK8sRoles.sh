#!/bin/bash 

dirname=`dirname "$0"`
thispath=`cd "$dirname" ; pwd `
thisScript=`basename "$0"`

#############################################################################
function showHelp {
    echo ""
    echo "This script will parse the yq output of the roles and turn them into csv files"
    echo ""
    echo "Parameters:"
    echo ""
    echo "-i|--input  = The input file containing the output of yq."
    echo "-o|--output = the output file containing the permissions information in csv form"
    echo "-x|--expand-verbs = Create a row for each apigroup, resource, verb combination (implies a * verb specification is expanded)"

}

function writeRecord {

   #  We want to build the verbs list in a certain order (alphabetical) so it's
   #  easier later to tell duplicates or supersets.
   #

#echo "writeRecord: resourceNames=$resourceNames"
   verbs2use=`echo "$verbs" | tr '|' '\n' | sort -u | tr '\n' '|'` 

   #  Most of the time, the resourceNames field will be blank, but we need to make
   #  sure the field has some value so that it will get processed.
   #  Set it to a value here so later we can recognize this is the case.
   if [[ "$resourceNames" == "" ]]
   then
      resourceNames="all"
   fi

   echo "\"$roleName\",\"$apiGroups\",\"$resourceNames\",\"$resources\",\"$verbs2use\"" >> "$outFile2"


}

#############################################################################
#  Main
#############################################################################
file=""
outFile=""
expandVerbs="0"

fullVerbList="create|delete|deletecollection|get|list|patch|update|watch|"

###  Parse the arguments

while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output)
      outFile="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--input)
      file="$2"
      shift # past argument
      shift # past value
      ;;
    -x|--expand-verbs)
      shift # past argument
      expandVerbs="1"
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

if [[ "$file" == "" ]]
then
  echo ""
  echo "ERROR: The name of the input file must be passed as a parameter"
  showHelp
  exit 22
else
  if [[ ! -f "$file" ]]
  then
     echo ""
     echo "ERROR: The input site file specified does not exist"
     showHelp
     exit 22
  fi
fi

if [[ "$outFile" == "" ]]
then
  echo ""
  echo "ERROR: The name of the output file must be passed as a parameter"
  showHelp
  exit 22
fi

  timestamp=`date +%Y%m%d%H%M%S%N`

  outFile2="/tmp/permissionsResource-${timestamp}.csv"

  #
  #  First, parse the input permissions.lst file.  This file was created by running this command
  #
  #   ky split -o byType -t <site.yaml>
  #   cd byType
  #   find . -name '*Role.*' | xargs yq eval '[.metadata.name,.rules[]]' - > ~/permissions.lst
  # 
  #

  newRole="1"
  role=""

  while read -r line; do

     #  Roles are divided by ---
     #  If we see this, write out any role information that is left from the last
     #  Role, and prepare to start processing a new one.
     #

     if [[ "$line" == "---" ]]
     then

   	newRole="1"

	if [[ "$roleName" != "" ]]
	then

	   #  Write out the last roles info

           writeRecord
	  
	   roleName=""
                 apiGroups=""
                 resources=""
                 verbs=""
 
	fi
 
     else

        if [[ "$newRole" == "1" ]]
        then

           roleName=`echo "$line" | cut -d' ' -f2`
  
           newRole="0"
           apiGroups=""

        else

           #  Under a role, it looks like this:
           #  - apigroups:
           #     - <group> (any number)
           #  - resourceNames:  (NOTE: this grouping is optional and seems to be rarely used)
           #     - name1
           #     - name2
           #  - resources:
           #     - resourc1
           #     - resource2
           #     - ... (any number)
           #  - verbs:
           #     - verb1
           #     - verb2
           #     - ... (any number)
           #
           #  this either repeats with another -apigroups, a --- signalling the end of this role, or no more lines
           #
#echo "process line=$line"
           if [[ "$line" == *"apiGroups"* ]]
           then
              if [[ "$apiGroups" != "" ]]
              then
                 # Write out the record
                 writeRecord
                 apiGroups=""
                 resourceNames=""
                 resources=""
                 verbs=""
              fi

              newApiGroup="1"
              
           else

              if [[ "$newApiGroup" == "1" ]]
              then

		      if [[ "$line" != *"resources"* && "$line" != *"resourceNames"* ]]
		      then
				#  Haven't reached the end yet of the apiGroups
				apiGroup=`echo "$line" | cut -d' ' -f2`
                                #  The default api Group in kubernetes is represented as a missing api group
                                #  Handle that here
                                if [[ "$apiGroup" == '""' ]]
                                then
                                   apiGroup="default"
                                fi

                                if [[ "$apiGroups" == "" ]]
                                then
                                   apiGroups="$apiGroup"
                                else
                                   apiGroups="$apiGroups|$apiGroup"
                                fi
		      else
				newApiGroup="0"

                                if [[ "$line" == *"resources"* ]]
                                then
                                   newResourceList="1" 
                                else
                                   newResourceNameList="1"
#echo "found resourceNames, echo $line"
                                fi
		      fi

              else

                 if [[ "$newResourceNameList" == "1" ]]
                 then
#echo "newResourceNameList=1"
                      if [[ "$line" != *"resources"* ]]
                      then
                                #  Haven't reached the end yet of the resourceNames
                                resourceName=`echo "$line" | cut -d' ' -f2`
#echo "found a resourceName to write out, echo $resourceName"
                                if [[ "$resourceNames" == "" ]]
                                then
                                   resourceNames="$resourceName"
                                else
                                   resourceNames="$resourceNames|$resourceName"
                                fi
#echo "resourceNames: $resourceNames"
                      else
                                newResourceNameList="0"
                                newResourceList="1"
                      fi

                 elif [[ "$newResourceList" == "1" ]]
                 then

                      if [[ "$line" != *"verbs"* ]]
                      then
                                #  Haven't reached the end yet of the resources
                                resource=`echo "$line" | cut -d' ' -f2 | tr -d "'"`
                                if [[ "$resource" == "*" ]]
                                then
                                   resource="all"
                                fi
                                #resource=`echo "$line" | cut -d' ' -f2`
                                if [[ "$resources" == "" ]]
                                then
                                   resources="$resource"
                                else
                                   resources="$resources|$resource"
                                fi
                      else
                                newResourceList="0"
                      fi

                 else
			#  Must be a verb

			verb=`echo "$line" | cut -d' ' -f2`
                        if [[ "$verbs" == "" ]]
                        then
                           verbs="$verb"
                        else
                           verbs="$verbs|$verb"
                        fi

                 fi

              fi
 
           fi                      

        fi

     fi

  done < "$file"

  #  Write out the last role info

if [[ "$roleName" != "" ]]
then

   #  Write out the last roles info

   writeRecord

   roleName=""
fi

 #  
 #  Now we should have a csv file in $outFile that has 1 row per apiGroup value
 #  However, the list of apiGroups can be more than 1.
 #  
 #  What we want to do now is create 1 row per resource in in each apiGroup
 #

  if [[ -f "$outFile" ]]
  then
     rm "$outFile"
  fi

  while IFS='"' read -r delim1 roleName delim3 apiGroups delim4 resourceNames delim5 resources delim6 verbs delim7; do

      if [[ "$apiGroups" == *"|"* ]]
      then
         IFS=$'|' apiGroupsList=($apiGroups)
      else
         apiGroupsList=("$apiGroups")
      fi
      numApiGroups=${#apiGroupsList[@]}

# TODO: Add logic here to deal with resourceNames, can't collapse across different resource Names
# Most apigroups will not have a blank resourceName

      IFS=$'|' resourceNameList=($resourceNames)
      numResourceNames=${#resourceNameList[@]}

      IFS=$'|' resourceList=($resources)
      numResources=${#resourceList[@]}

      for ((i=0; i<$numApiGroups; i++ ))
      do
              apiGroup="${apiGroupsList[$i]}"
   #           echo "Processing API Group=$apiGroup"

	      for ((j=0; j<$numResourceNames; j++ ))
	      do
		      resourceName="${resourceNameList[$j]}"

       #              echo "Processing resourceName=$resourceName"

		      for ((k=0; k<$numResources; k++ ))
		      do
			  resource="${resourceList[$k]}"
            #             echo "Processing resource=$resource"

			  if [[ "$expandVerbs" == "1" ]]
			  then

			    hasWildcard=`echo "$verbs" | grep "'*'"`

			    if [[ "$hasWildcard" != "" ]]
			    then
			       verbs="$fullVerbList"
			       echo "Found wildcard verb for apiGroup=$apiGroup, resource=$resource, expanding verbs"
			    fi
			  fi

			  echo "\"$roleName\",\"$apiGroup\",\"$resourceName\",\"$resource\",\"$verbs\"" >> "$outFile"

		      done
              done
      done

  done < "$outFile2"

  rm "$outFile2"

