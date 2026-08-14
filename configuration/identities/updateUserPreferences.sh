#!/bin/bash 

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
   echo ""
   echo "This script can be used to update user preferences Viya applications rely on."
   echo ""
   echo "Usage:"
   echo ""
   echo "1. Authenticate with an administrative user to the sas-viya CLI: sas-viya --profile <profile-name> auth login"
   echo "2. Set the SAS_CLI_PROFILE environment variable: export SAS_CLI_PROFILE=<profile-name>"
   echo "3. Updates a preference for SAS Studio (performs a dry-run): ./updateUserPreferences.sh --pref-key studioPreferences.backgroundSubmit.jobExpiresAfter --pref-value PT168H --pref-application SASStudio --users my-user-id"
   echo ""
   echo "Parameters:"
   echo ""
   echo "  --help = show this help content"
   echo "  -u|--users = A comma delimitted list of user ids to process. If this is not specified, all users in the system will be scanned."
   echo "  --pref-key = The preference key. Must be specified with --pref-value and --pref-application."
   echo "  --pref-application = The preference application. Must be specified with --pref-key and --pref-value."
   echo "  --pref-value = The preference value. Must be specified with --pref-key and --pref-application."
   echo "  --pref-file = A csv file containing the preference key, application, and value. Can be used if multiple preferences need to be updated for each user."
   echo " -c|--commit = Persists any modifications for the users. Without this option, the script performs a dry-run by default."
   echo "  --force = If the preference has already been set, this will allow the existing value to be overridden."   
   echo "  -k|--insecure = Ignore using certificates when issuing commands"
}

function updatePreferences {
    local userId="$1"
    if [[ "$preferenceFile" != "" ]]
    then
        while IFS='"' read -r delim1 key delim2 application delim3 value delim4; do
            if [[ "$key" == "key" && "$value" == "value" ]]
            then
                continue
            else
                updatePreference "$userId" "$key" "$value" "$application"
            fi
        done < "$preferenceFile"

    elif [[ "$preferenceKey" != "" && "$preferenceValue" != "" ]]
    then
        updatePreference "$userId" "$preferenceKey" "$preferenceValue" "$preferenceApplication"
    else
        echo "WARNING: Invalid preference settings"
    fi
}

function updatePreference {
    local userId="$1"
    local key="$2"
    local value="$3"
    local application="$4"
    
    local timestamp=`date +%Y%m%d%H%M%S%N`
    tempOutput="preferences-$timestamp.json"

    echo "Updating preference '$key' for user: $userId"
    uri="preferences/preferences/$userId?filter=and(eq(id,'$key'),eq(application,'$application'))"
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    rm "$tempOutput"

    if [[ "$count" == "1" ]]
    then
        if [[ "$force" == "1" ]]
        then
            echo "User preference '$key' exists. Overriding value."
        else
            echo "User preference '$key' exists. Skipping update. Use the --force option to override this value if needed."
            return
        fi
    else
        echo "User preference '$key' does not exist. Creating new preference."
    fi

    if [[ "$commit" == "1" ]]
    then
        local prefUri="preferences/preferences/$userId/$preferenceKey"
        json="{\"version\": 1, \"id\": \"$key\", \"application\": \"$application\", \"value\": \"$value\"}"
        statusCode=`curl -s "$secureOption" --write-out '\n%{http_code}' --output /dev/null "$urlRoot/$prefUri" -d "$json" -X PUT -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken"`           
        statusCode=`echo $statusCode | tail -n1`
        if [[ "$statusCode" == "200" || "$statusCode" == "201" ]]
        then
            echo "  Update succeeded."
            updateCount=$(( updateCount + 1 ))
        else
            echo "  Update failed.  Reason: $statusCode"
        fi
    fi
}

#################################################################
#  Main
#################################################################
secureOption=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--commit)
      commit="1"
      shift # past argument
      ;;
    --force)
      force="1"
      shift # past argument
      ;;
    -u|--users)
      users="$2"
      shift # past argument
      shift # past value
      ;;
    --pref-key)
      preferenceKey="$2"
      shift # past argument
      shift # past value
      ;;
    --pref-value)
      preferenceValue="$2"
      shift # past argument
      shift # past value
      ;;
    --pref-application)
      preferenceApplication="$2"
      shift # past argument
      shift # past value
      ;;
    --pref-file)
      preferenceFile="$2"
      shift # past argument
      shift # past value
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

if [[ "$preferenceFile" != "" ]]
then
    if [[ ! -f "$preferenceFile" ]]
    then
        echo "ERROR: The specified preference file '$preferenceFile' does not exist."
        exit 0
    fi
elif [[ "$preferenceKey" == "" || "$preferenceValue" == "" ]]
then
    echo "ERROR: A preference key/value must be specified."
    exit 0
fi


# pull in the shared set of functions and validate the user's CLI profile
. "$thispath/../../common/_shared.sh"
echo "Validate Viya CLI configuration"
validateCLISetup

# grab the access token and endpoint information from the CLI profile - we'll need it later to issue direct service requests
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

echo "---------------------------------------------------"
if [[ "$commit" != "1" ]]
then
    echo "NOTE: Performing a dry-run. Use the --commit flag to persist any changes."
fi
echo ""

usersOutput="users.json"
identitiesUri="identities/users?limit=100"
if [[ "$users" != "" ]]
then
    echo "Fetching users on the system"
    filter="in(id,"
    counter=0
    IFS=',' read -ra userList <<< "$users"
    for user in "${userList[@]}"; do
        counter=$((counter+1))
        if [[ "$counter" -gt 1 ]]
        then
            filter+=",'$user'"
        else
            filter+="'$user'"
        fi
    done
    filter+=")"
    identitiesUri+="&filter=$filter"
else
   echo "Fetching all users on the system"
fi

usersExist=false
pageNumber=1
while [[ "$NEXT_LINK" != "" || "$pageNumber" == "1" ]]
do
    curl -s $secureOption "$urlRoot/$identitiesUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $usersOutput > /dev/null
    while IFS="|" read -r id name; do
        echo ""
        usersExist=true
        updatePreferences "$id"
    done< <(jq -r '.items[] | "\(.id)|\(.name)"' $usersOutput)

    NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $usersOutput`
    identitiesUri="$NEXT_LINK"
    pageNumber=$(( pageNumber + 1 ))
rm $usersOutput
done

if [[ "$usersExist" == "false" ]]
then
    echo "No users were found with the specified criteria; --users='$users'"
fi
