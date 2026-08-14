#!/bin/bash

#######################################################
function showHelp {
   echo ""
   echo "This script generates a UID value for specified users based on the 'getent passwd' command. This script"
   echo "will create an output file that can then be fed into the loadUID.sh script to set the UID values for the users"
   echo "within a Viya deployment."
   echo ""
   echo " Parameters:"
   echo ""
   echo "  --help = show this help content"
   echo "  -f|--user-file = use this file to load from (required)"
   echo "  -b|--identities-bulkload-format = use the same format for the csv file as the SAS Viya Identities CLI bulkload feature"
   echo "  -o|--output = the output file to create, that can then be used within the loadUID.sh script"
}

#################################################################
#  Main
#################################################################

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--user-file|--file)
      userFile="$2"
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

#  Handle some high level actions first
if [[ "$action" == "help" ]]
then
    showHelp
    exit 0
fi

if [[ "$userFile" == "" ]]
then
    echo "ERROR: user file must be passed as a parameter."
    exit 22
fi
if [[ ! -f "$userFile" ]]
then
    echo "ERROR: the user file, $userFile, does not exist."
    exit 22
fi

if [[ "$outFile" == "" ]]
then
    echo "ERROR: The name of the output file to create must be passed as a parameter"
    exit 22
fi

echo "---------------------------------------------------"

rc=0
timestamp=`date +%Y%m%d%H%M%S%N`
if [[ "$bulkloadFormat" != "1" ]]
then
    #  The input lines are in csv format, with each field surrounded by quotes
    #  The fields might contain , thus we can't do a delimited read on comma as the delimiter
    #  Instead, we will use the quote, which will allow for the embedded commas and will strip the quotes from each of the fields
    #
    #  Make sure the headers however are only included if we are not using the bulkload format
    echo "\"id\",\"name\",\"uid\",\"gid\"" > "$outFile"
fi

while IFS='"' read -r delim1 id delim2 name delim3 state delim4 description; do

    if [[ "$state" == "state" && "$description" == "description" ]]
    then
        echo "Skipping header line"
    else
        if [[ "$state" == "active" ]]
        then
            echo "Processing user id $id, user name=$name"

            getentResultsFile="/tmp/getent-$id-$timestamp.txt"
                       
            getent passwd "$id" > "$getentResultsFile"

            uid=`cat "$getentResultsFile" | cut -d':' -f3`
            gid=`cat "$getentResultsFile" | cut -d':' -f4`

            if [[ "$uid" != "" ]]
            then
                if [[ "$bulkloadFormat" == "1" ]]
                then
                    echo "user,$id,$uid,$gid" >> "$outFile"
                else
                    echo "\"$id\",\"$name\",\"$uid\",\"$gid\"" >> "$outFile"
                fi
            else
                echo "WARNING: Unable to retrieve uid for user id $id, group name=$name"
            fi
            rm "$getentResultsFile"
        fi
    fi

done < "$userFile"

exit $rc
