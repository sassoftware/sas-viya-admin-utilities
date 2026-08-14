#!/bin/bash 

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`

#
# This script will take the information from the input file and load the gid information 
# in the identities service.
#

function showHelp {
   echo ""
   echo "This script will load the passed user uid and gid information into the identities service."
   echo ""
   echo " Parameters:"
   echo ""
   echo "  --help = show this help content"
   echo "  -f|--user-file|--file = use this file to load from (required)"
   echo "  -b|--identities-bulkload-format = use the same format for the csv file as the SAS Viya Identities CLI bulkload feature"
   echo "  -k|--insecure = Ignore using certificates when issuing commands"

}

#################################################################
#  Main
#################################################################
secureOption=""

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
    -k|--insecure)
      shift # past argument
      secureOption="-k"
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

# pull in the shared set of functions and validate the user's CLI profile
. "$thispath/../_shared.sh"
echo "Validate Viya CLI configuration"
validateCLISetup

echo "---------------------------------------------------"

timestamp=`date +%Y%m%d%H%M%S%N`
rc=0

if [[ "$bulkloadFormat" == "1" ]]
then
    #  When the bulkloadFormat option is set, we are assuming the format of the input csv file is the same as the format
    #  used by the SAS Viya Identities CLI, with the following columns: identityType, identityId, UID, GID
    cliLogFile="/tmp/sascli-uid-$timestamp.log"
    "$sasCLICommand" $secureOption -y identities bulkload-user-identifiers -f "$userFile" 2>&1 | tee "$cliLogFile"

    #  Unfortunately, the sas cli doesn't set the return code if failure happens, so try to determine it from looking at the log.
    hasErrors=`grep "errors have occurred" "$cliLogFile"`
    if [[ "$hasErrors" != "" ]]
    then
        echo "ERROR: Errors occurred during defining uid for user id $id, group name=$name"
    fi
    rm "$cliLogFile"
else
    #  The input lines are in csv format, with each field surrounded by quotes
    #  The fields might contain , thus we can't do a delimited read on comma as the delimiter
    #  Instead, we will use the quote, which will allow for the embedded commas and will strip the quotes from each of the fields
    while IFS='"' read -r delim1 id delim2 name delim3 uid delim4 gid delim5; do

        if [[ "$id" == "id" && "$name" == "name" ]]
        then
            echo "Skipping header line"
        else
            echo "Processing user id $id, user name=$name"

            if [[ "$uid" != "" ]]
            then              
                cliLogFile="/tmp/sascli-$id-$timestamp.log"

                # TODO: Is there a way for us to indicate to override the uid that already exists for this user, or to find out if it already exists, and if so
                #       what is it and how does it compare to this one?

                if [[ "$gid" == "" ]]
                then
                    echo "WARNING: Primary gid information missing for user id $id, user name=$name, setting gid=uid"
                    "$sasCLICommand" $secureOption -y identities update-user --id "$id" --uid "$uid" --gid "$uid" 2>&1 | tee "$cliLogFile"
                else
                    "$sasCLICommand" $secureOption -y identities update-user --id "$id" --uid "$uid" --gid "$gid" 2>&1 | tee "$cliLogFile"
                fi

                #  Unfortunately, the sas cli doesn't set the return code if failure happens, so try to determine it from looking at the log.
                hasErrors=`grep "errors have occurred" "$cliLogFile"`
                if [[ "$hasErrors" != "" ]]
                then
                    echo "ERROR: Errors occurred during defining uid for user id $id, user name=$name"
                fi
                rm "$cliLogFile"
            else
                echo "WARNING: No uid entered, skipping user id $id, user name=$name"
            fi
        fi

    done < "$userFile"
fi
exit $rc
