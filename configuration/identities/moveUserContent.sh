#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
   echo ""
   echo "This script is used to move content (in the SAS Content tree) from one user id to another. This script should only be used in situations"
   echo "where a user's id has changed, possibly due to a difference in case, and content persisted in their home folder needs to be moved to a new location."
   echo ""
   echo "Usage:"
   echo ""
   echo "1. Authenticate with an administrative user to the sas-viya CLI: sas-viya --profile <profile-name> auth login"
   echo "2. Set the SAS_CLI_PROFILE environment variable: export SAS_CLI_PROFILE=<profile-name>"
   echo "3. Move content from an original userid to a new userid (performs a dry-run): ./moveUserContent.sh --original-user-id test.user@example.com --new-userid Test.User@example.com"
   echo "4. Move content from an original userid to a new userid (commits the changes): ./moveUserContent.sh --original-user-id test.user@example.com --new-userid Test.User@example.com --commit"
   echo "5. Move content for all userids in file: (performs a dry-run): ./moveUserContent.sh --input-user-file my-users.csv"
   echo ""
   echo "Parameters:"
   echo ""
   echo " -o|--original-userid = The original userid."
   echo " -n|--new-userid = The new userid."
   echo " -i|--input-user-file = A comma delimitted list of original userids / new user ids. Allows for updating content for multiple users in bulk."
   echo " --original-root-folder-id = The id of the original 'Users' root folder. This must be specified in situations where multiple exist."
   echo " --new-root-folder-id = The id of the new 'Users' root folder. This must be specified in situations where multiple exist."
   echo " -c|--commit = Persists any modifications for the users. Without this option, the script performs a dry-run by default."
   echo ""
}

function getUserRootFolders {
    # Start by fetching the Users root folder(s). In most deployments there should only be 1, however there have been situations
    # where a 2nd folder is created.
    local rootFoldersUri="folders/rootFolders?filter=eq(type,userRoot)"
    local rootFoldersOutput="rootFolders.json"
    curl -s "$secureOption" "$urlRoot/$rootFoldersUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $rootFoldersOutput > /dev/null
    readarray -t rootFolderContents < <(jq --compact-output '.items[]' $rootFoldersOutput)
    for item in "${rootFolderContents[@]}"; do
        id=$(jq --raw-output '.id' <<< "$item")
        rootFolders+=("/folders/folders/$id")
    done
    rm $rootFoldersOutput
}

function getUserHomeFolderInRoot {
    local userId="$1"
    local rootFolderId="$2"
    userFolderUri="$rootFolderId/members?filter=eq(\$tertiary,name,'$userId')"
    local homeFolderOutput="homeFolder.json"
    curl -s "$secureOption" "$urlRoot/$userFolderUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $homeFolderOutput > /dev/null
    homeFolderId=`jq -r '.items[0] | .uri' $homeFolderOutput`
    rm $homeFolderOutput
    echo $homeFolderId
}

function getUserHomeFolderId {
    local userId="$1"
    local rootFolderId="$2"
    local homeFolderId=""
    if [[ "$rootFolderId" == "" ]]
    then
        # We don't know the id of the Users root folder(s). Scan through each one - note that in most cases, there should only
        # be one, however this script supports the existence of multiple in the event that a second Users folder was created because
        # of an error.
        for rootId in "${rootFolders[@]}"; do
            # fetch the user's home folder using a case sensitive match - there should only be one (if any) returned
            homeFolderId=`getUserHomeFolderInRoot $userId $rootId`
            if [[ "$homeFolderId" != "" && "$homeFolderId" != "null" ]]
            then
                break
            fi
        done
    else
        # A root folder id was specified - use it to fetch the appropriate user id - using a case sensitive match
        homeFolderId=`getUserHomeFolderInRoot $userId /folders/folders/$rootFolderId`
    fi
    echo $homeFolderId
}

#############################
# The original function for fetching a user's home folder. This does not work with Viya 4 though since the myFolder lookup
# is case insensitive.
#############################
function getUserHomeFolderId_Old {
    local userId="$1"

    # start by fetching the user's My folder
    local myFolderUri="folders/folders/@myFolder?userId=$userId"
    local myFolderOutput="myFolder.json"
    curl -s "$secureOption" "$urlRoot/$myFolderUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $myFolderOutput > /dev/null
    
    local homeFolderId=""
    local myFolderId=`jq -r '.id' $myFolderOutput`
    if [[ "$myFolderId" != "" && "$myFolderId" != "null" ]]
    then
        homeFolderId=`jq -r '.parentFolderUri' $myFolderOutput`
    fi
    rm $myFolderOutput
    echo $homeFolderId
}

function moveMember {
    if [[ "$commit" == "1" ]]
    then
        local memberUri="$1"
        local targetParentUri="$2"
        local moveInput="{\"parentFolderUri\": \"$targetParentUri\"}"

        # on some systems, curl is returning the output in the form of "000{response-body}{status-code}", where the actual response code
        # is bundled into the same line as the body. to work around that, make sure we're printing a new line in between
        response=$(curl --silent "$secureOption" --write-out '\n%{http_code}' --output /dev/null "$urlRoot/$memberUri" -X PATCH --data-raw "$moveInput" -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken")
        response=`echo $response | tail -n1`
        if [[ "$response" == "200" ]]
        then
            echo "  Move successful"
        else
            echo "  Move failed: $response"
        fi
    fi
}

function compareFolders {
    local delimiter="/"
    local sourceFolderUri="$1"
    local targetFolderUri="$2"

    # fetch source folder contents
    local sourceId=${sourceFolderUri##*${delimiter}}
    local sourceFolderOutput="source_$sourceId.json"
    curl -s "$secureOption" "$urlRoot/$sourceFolderUri/members" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $sourceFolderOutput > /dev/null

    # fetch target folder contents
    local targetId=${targetFolderUri##*${delimiter}}
    local targetFolderOutput="target_$targetId.json"
    curl -s "$secureOption" "$urlRoot/$targetFolderUri/members" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $targetFolderOutput > /dev/null

    # iterate through the source folder's contents
    readarray -t sourceFolderContents < <(jq --compact-output '.items[]' $sourceFolderOutput)
    for item in "${sourceFolderContents[@]}"; do
        name=$(jq --raw-output '.name' <<< "$item")
        contentType=$(jq --raw-output '.contentType' <<< "$item")
        echo "Processing folder member (name = '$name', type = '$contentType')"

        # search for the member within the target folder
        targetUri=`jq -r '.items[] | select(.contentType == "'"$contentType"'" and .name == "'"$name"'") | .uri' $targetFolderOutput`
        if [[ "$contentType" == "folder" || "$contentType" == "myFolder" || "$contentType" == "applicationDataFolder" || "$contentType" == "trashFolder" || "$contentType" == "favoritesFolder" || "$contentType" == "historyFolder" ]]
        then
            if [[ "$targetUri" != "" ]]
            then
                echo "  Target folder exists - processing members"
                uri=$(jq --raw-output '.uri' <<< "$item")
                compareFolders "$uri" "$targetUri"
            else
                echo "  Target folder does not exist - moving"
                memberUri=$(jq --raw-output '.links[] | select(.rel == "self") | .uri' <<< "$item")
                moveMember "$memberUri" "$targetFolderUri"
            fi
        else
            if [[ "$targetUri" != "" ]]
            then
                echo "  Target member exists - skipping"
            else
                echo "  Target member does not exist - moving"
                memberUri=$(jq --raw-output '.links[] | select(.rel == "self") | .uri' <<< "$item")
                moveMember "$memberUri" "$targetFolderUri"
            fi
        fi

    done

    rm $sourceFolderOutput
    rm $targetFolderOutput
}

function moveUserContent {
    local oldId="$1"
    local newId="$2"        

    # load the root folders (if necessary)
    if [[ -z "${rootFolders[*]}" ]]
    then
        getUserRootFolders
    fi

    local oldHomeFolderId=`getUserHomeFolderId $oldId $originalUsersRootFolderId`
    if [[ "$oldHomeFolderId" == "" || "$oldHomeFolderId" == "null" ]]
    then
        echo "WARNING: Could not find home folder for original user $oldId"
        return
    fi

    local newHomeFolderId=`getUserHomeFolderId $newId $newUsersRootFolderId`
    if [[ "$newHomeFolderId" == "" || "$newHomeFolderId" == "null" ]]
    then
        echo "WARNING: Could not find home folder for new user $newId"
        return
    fi

    if [[ "$oldHomeFolderId" == "$newHomeFolderId" ]]
    then
        echo "Skipping user '$oldId' - user folder locations are the same"
    else
        echo "Moving user content (original userid = $oldId, new userid = $newId)"
        compareFolders $oldHomeFolderId $newHomeFolderId
    fi
    echo ""
}

#################################################################
#  Main
#################################################################

originalUsersRootFolderId=""
newUsersRootFolderId=""

#  Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--original-userid)
      oldUserId="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--new-userid)
      newUserId="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--input-user-file)
      userFile="$2"
      shift # past argument
      shift # past value
      ;;
    --original-root-folder-id)
      originalUsersRootFolderId="$2"
      shift # past argument
      shift # past value
    ;;
    --new-root-folder-id)
      newUsersRootFolderId="$2"
      shift # past argument
      shift # past value
    ;;
    -c|--commit)
      commit="1"
      shift # past argument
      ;;
    -k|--insecure)
      secureOption="-k"
      shift # past argument
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

# pull in the shared set of functions and validate the user's CLI profile
. "$thispath/../../common/_shared.sh"
echo "Validate Viya CLI configuration"
validateCLISetup

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

echo "---------------------------------------------------"
if [[ "$commit" != "1" ]]
then
    echo "NOTE: Performing a dry-run. Use the --commit flag to persist any changes."
fi
echo ""

rootFolders=()
if [[ "$userFile" != "" ]]
then
    if [[ ! -f "$userFile" ]]
    then
        echo "ERROR: The file '$userFile' does not exist"
        showHelp
        exit 22
    fi

    while IFS=, read -r oldId newId; do
        moveUserContent "$oldId" "$newId"
    done < "$userFile"
else
    if [[ "$oldUserId" == "" || "$newUserId" == "" ]]
    then
        echo "ERROR: The original and new userids must be specified"
        showHelp
        exit 22
    fi
    moveUserContent "$oldUserId" "$newUserId"
fi
