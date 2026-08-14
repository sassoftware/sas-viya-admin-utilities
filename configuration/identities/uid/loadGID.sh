#!/bin/bash 

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
   echo ""
   echo "This script will load the passed group GID information into the identities service."
   echo ""
   echo " Parameters:"
   echo ""
   echo "  --help = show this help content"
   echo "  -f|--group-file = use this file to load from (required)"
   echo "  -b|--identities-bulkload-format = use the same format for the csv file as the SAS Viya Identities CLI bulkload feature"
   echo "  -k|--insecure = Ignore using certificates when issuing commands"
}

#
# This script will take the information from the input file and load the gid information 
# in the identities service.
#

#################################################################
#  Main
#################################################################
secureOption=""

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
    "$sasCLICommand" $secureOption -y identities bulkload-group-identifiers -f "$groupFile" 2>&1 | tee "$cliLogFile"

    #  Unfortunately, the sas cli doesn't set the return code if failure happens, so try to determine it from looking at the log.
    hasErrors=`grep "errors have occurred" "$cliLogFile"`
    if [[ "$hasErrors" != "" ]]
    then
        echo "ERROR: Errors occurred during defining uid for group id $id, group name=$name"
    fi
    rm "$cliLogFile"
else
    #  The input lines are in csv format, with each field surrounded by quotes
    #  The fields might contain , thus we can't do a delimited read on comma as the delimiter
    #  Instead, we will use the quote, which will allow for the embedded commas and will strip the quotes from each of the fields
    while IFS='"' read -r delim1 groupid delim2 groupName delim3 gid delim4; do

        if [[ "$groupid" == "id" && "$groupName" == "name" ]]
        then
            echo "Skipping header line"
        else
            echo "Processing group id $groupid, group name=$groupName"

            if [[ "$gid" != "" ]]
            then
                cliLogFile="/tmp/sascli-$groupid-$timestamp.log"

                # TODO: Is there a way for us to indicate to override the gid that already exists for this group, or to find out if it already exists, and if so
                #       what is it and how does it compare to this one?
                "$sasCLICommand" $secureOption -y identities update-group --id "$groupid" --gid "$gid" 2>&1 | tee "$cliLogFile"

                #  Unfortunately, the sas cli doesn't set the return code if failure happens, so try to determine it from looking at the log.
                hasErrors=`grep "errors have occurred" "$cliLogFile"`
                if [[ "$hasErrors" != "" ]]
                then
                    echo "ERROR: Errors occurred during defining gid for group id $groupid, group name=$groupName"
                fi
                rm "$cliLogFile"
            else
                echo "WARNING: No gid entered, skipping group id $groupid, group name=$groupName"
            fi
        fi

    done < "$groupFile"
fi
exit $rc
