#!/bin/bash

#######################################################
function showHelp {
   echo ""
   echo "This script generates a GID value for specified groups based on the 'getent group' command. This script"
   echo "will create an output file that can then be fed into the loadGID.sh script to set the GID values for the groups"
   echo "within a Viya deployment."
   echo ""
   echo " Parameters:"
   echo ""
   echo "  --help = show this help content"
   echo "  -f|--group-file = use this file to load from (required)"
   echo "  -b|--identities-bulkload-format = use the same format for the csv file as the SAS Viya Identities CLI bulkload feature"
   echo "  -o|--output = the output file to create, that can then be used within the loadGID.sh script"

}

#################################################################
#  Main
#################################################################

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--group-file|--file)
      groupFile="$2"
      shift # past argument
      shift # past value
      ;;
    -b|--identities-bulkload-format)
      bulkloadFormat="1"
      shift # past argument
      ;;
    -o|--output)
      outFile="$2"
      shift # past argument
      shift # past value
      ;;
    --help)
      showHelp
      shift # past argument
      exit 0
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

if [[ "$groupFile" == "" ]]
then
    echo "ERROR: group file must be passed as a parameter."
    exit 22
fi
if [[ ! -f "$groupFile" ]]
then
    echo "ERROR: group file, $groupFile, does not exist."
    exit 22
fi

if [[ "$outFile" == "" ]]
then
    echo "ERROR: The name of the output file to create must be passed as a parameter"
    exit 22
fi

rc=0
if [[ "$bulkloadFormat" != "1" ]]
then
    #  The input lines are in csv format, with each field surrounded by quotes
    #  The fields might contain , thus we can't do a delimited read on comma as the delimiter
    #  Instead, we will use the quote, which will allow for the embedded commas and will strip the quotes from each of the fields
    #
    #  Make sure the headers however are only included if we are not using the bulkload format
    echo "\"id\",\"name\",\"gid\"" > "$outFile"
fi

while IFS='"' read -r delim1 groupid delim2 groupName delim3 providerId delim4 groupState delim5 groupDescription; do

    if [[ "$groupState" == "state" && "$groupDescription" == "description" ]]
    then
        echo "Skipping header line"
    elif [[ $providerId == "local" ]]
    then
        echo "Skipping custom group $groupid"
    elif [[ $groupState != "active" ]]
    then
        echo "Skipping inactive group $groupid"
    else
        echo "Processing group id $groupid, group name=$groupName"

        # TODO: Is there less expensive way to get this information?  getent group also returns all the members of that group
        gid=`getent group "$groupid" | cut -d':' -f3`
        if [[ "$gid" != "" ]]
        then
            if [[ "$bulkloadFormat" == "1" ]]
            then
                echo "group,$groupid,$gid" >> "$outFile"
            else
                echo "\"$groupid\",\"$groupName\",\"$gid\"" >> "$outFile"
            fi
        else
            echo "WARNING: Unable to retrieve gid for group id $groupid, group name=$groupName"
        fi
    fi

done < "$groupFile"

exit $rc
