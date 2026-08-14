#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
   echo ""
   echo "This script is used to fetch the list of registered groups from a SAS Viya deployment, and outputs the"
   echo "results to a CSV file located in the identities/groups directory. This CSV file can then be used as input"
   echo "for other scripts or processes in this project."
   echo ""
   echo "Usage:"
   echo ""
   echo "1. Authenticate with an administrative user to the sas-viya CLI: sas-viya --profile <profile-name> auth login"
   echo "2. Set the SAS_CLI_PROFILE environment variable: export SAS_CLI_PROFILE=<profile-name>"
   echo "3. Fetch the list of groups: ./fetchGroups.sh --dir <directory>"
   echo ""
   echo "Parameters:"
   echo ""
   echo "  --help = show this help content"
   echo "  -d|--dir = The directory where the group CSV file will be saved."
   echo "  -m|--include-memberships = If set, includes group membership information in the output."
   echo "  -k|--insecure = Ignore using certificates when issuing commands"
}

#################################################################
#  Main
#################################################################
secureOption=""

#  Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--dir)
      dir="$2"
      shift # past argument
      shift # past value
      ;;
    -m|--include-memberships)
      includeMemberships="1"
      shift # past argument
      shift # past value
      ;;
    -k|--insecure)
      secureOption="-k"
      shift # past argument
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

# pull in the shared set of functions and validate the user's CLI profile
. "$thispath/../../common/_shared.sh"
echo "Validate Viya CLI configuration"
validateCLISetup

echo "---------------------------------------------------"

groupDir="$dir/groups"
if [[ ! -d "$groupDir" ]]
then
    mkdir "$groupDir"
fi

groupsLog="$groupDir/groups.log"

#  grab the access token and endpoint information from the CLI profile - we'll need it later to issue direct service requests
accessToken=$(getAccessToken)
if [[ $accessToken == "" ]]
then
    echo "ERROR: Unable to locate access token"
    rc=2
    exit $rc
fi

urlRoot=$(getUrlRoot)
if [[ $urlRoot == "" ]]
then
    echo "ERROR: Unable to locate SAS endpoint"
    rc=2
    exit $rc
fi

# This command isn't quite right since some users have a description field but most don't, this doesn't deal with that correctly
groupsFile="$groupDir/groups.csv"
tempGroupsJson="$groupDir/groups.temp.json"

#
# Fetch the list of groups using the REST API directly
# We need to do this here in order to retrieve the providerId field for each group, to tell us if we're 
# dealing with a custom group or not.  The sas-identities CLI does not return this information.
#
echo "Getting the list of groups"
curl "$secureOption" -L -X GET "${urlRoot}/identities/groups" -H "Accept: application/json" -H "Authorization: Bearer ${accessToken}" | jq '[.items[] | {id: .id, name: .name, providerId: .providerId, state: .state, description: .description}]' | tee "$tempGroupsJson" | tee -a "$groupsLog"
if [[ -f "$tempGroupsJson" ]]
then
    # add header line to output file
    echo "\"id\",\"name\",\"providerId\",\"state\",\"description\"" > "$groupsFile"

    # Now add the data rows
    jq '.[] | map(.) | @csv' "$tempGroupsJson" | sed 's/\\\"/\"/g' | sed 's/^\"\(.*\)\"$/\1/' | tee -a "$groupsFile" | tee -a "$groupsLog"

    rm "$tempGroupsJson"
fi

# 
# For each group, get the memberships
#
if [[ "$includeMemberships" == "1" ]]
then
    while IFS=, read -r groupId groupName groupStatus groupDescription; do

        # the items in the csv are surrounded by quotes
        groupId=`echo $groupId | tr -d '"'`

        # Skip the header row if passed
        if [[ "$groupId" != "id" ]]
        then
            echo "Fetching memberships for group $groupId"
            membersFile="$groupDir/group-members-$groupId.csv"
            echo "\"id\",\"name\",\"type\"" > "$membersFile"

            "$sasCLICommand" "$secureOption" --output json --y identities list-members --group-id "$groupId" | jq '.items[] | {id: .id, name: .name, type: .type} | map(.) | @csv' | sed 's/\\\"/\"/g' | sed 's/^\"\(.*\)\"$/\1/' | tee -a "$membersFile"
        fi

    done < "$groupsFile"
fi