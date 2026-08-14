#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
   echo ""
   echo "This script is used to fetch the list of registered users from a SAS Viya deployment, and outputs the"
   echo "results to a CSV file located in the identities/users directory. This CSV file can then be used as input"
   echo "for other scripts or processes in this project."
   echo ""
   echo "Usage:"
   echo ""
   echo "1. Authenticate with an administrative user to the sas-viya CLI: sas-viya --profile <profile-name> auth login"
   echo "2. Set the SAS_CLI_PROFILE environment variable: export SAS_CLI_PROFILE=<profile-name>"
   echo "3. Fetch the list of users: ./fetchUsers.sh --dir <directory>"
   echo ""
   echo "Parameters:"
   echo ""
   echo "  --help = show this help content"
   echo "  -d|--dir = The directory where the user CSV file will be saved."
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

usersDir="$dir/users"
if [[ ! -d "$usersDir" ]]
then
    mkdir "$usersDir"
fi

userLog="$usersDir/users.log"
userList="$usersDir/users.csv"
tempUserJson="$usersDir/users.temp.json"

# This command isn't quite right since some users have a description field but most don't, this doesn't deal with that correctly
# Can't use the -r option on jq since some of the fields may have special characters, so use sed to clean up the file
"$sasCLICommand" "$secureOption" -y --output json identities list-users | jq '[.items[] | {id: .id, name: .name, state: .state, description: .description}]' | tee "$tempUserJson" | tee -a "$userLog"

if [[ -f "$tempUserJson" ]]
then
    # add header line to output file
    echo "\"id\",\"name\",\"state\",\"description\"" > "$userList"

    # Now add the data rows
    jq '.[] | map(.) | @csv' "$tempUserJson" | sed 's/\\\"/\"/g' | sed 's/^\"\(.*\)\"$/\1/' | tee -a "$userList" | tee -a "$userLog"
    rm "$tempUserJson"
fi
