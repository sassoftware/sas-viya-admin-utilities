#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
    echo ""
    echo "This script is used to upload files to a target location on the SAS Server."
    echo ""
    echo "Usage:"
    echo ""
    echo "1. Authenticate by either passing in the hostname/user/password values directly to this script, or by using the sas-viya CLI as follows:"
    echo "   sas-viya --profile <profile-name> auth login"
    echo "   export SAS_CLI_PROFILE=<profile-name>"
    echo ""
    echo "2. Upload a new file: ./uploadFile.sh --compute-context-name {compute-context} --file myfile.txt --target-location /remote/directory"
    echo "3. Upload and overwrite an existing file: ./uploadFile.sh --compute-context-name {compute-context} --file myfile.txt --target-location /remote/directory --force"
    echo ""
    echo "Parameters:"
    echo ""
    echo " -h|--hostname = The hostname of the SAS server."
    echo " -u|--user = The user name to authenticate as."
    echo " -p|--password = The password for the user."
    echo " -f|--file = The input file to upload."
    echo " -t|--target-location = The target location on the SAS server to upload the file to."
    echo " -c|--compute-context-name = The name of the compute context to use."
    echo " --force = If specified, will overwrite an existing file at the target location."
    echo " -k|--insecure = If specified, will skip SSL certificate validation."
    echo ""
}

function uploadFile {
    local inputFile="$1"
    local targetLocation="$2"
    local sessionId="$3"
    if [[ "${targetLocation: -1}" != "/" ]]
    then
        targetLocation="${targetLocation}/"
    fi
    local fileName=`basename "$inputFile"`
    local fileLocation="${targetLocation}${fileName}"
    local encodedFileLocation="${fileLocation//\//~fs~}"

    # check to see if the file exists
    headers="headers.txt"
    local uri="compute/sessions/$sessionId/files/$encodedFileLocation"
    response=$(curl -s "$secureOption" "$urlRoot/$uri" --write-out '\n%{http_code}' --output /dev/null -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken" -D $headers)
    response=`echo $response | tail -n1`
    if [[ "$response" == "200" ]]
    then
        if [[ "$force" != "1" ]]
        then
            echo "The file already exists in this location. Use --force to overwrite."
            return
        else
            echo "Overwriting existing file."
            etag=`grep -i 'ETag:' $headers | tr -d ' ' | tr -d '\r' | cut -d':' -f2`
        fi
    fi
    rm $headers

    ifMatchHeader=""
    uri="compute/sessions/$sessionId/files/$encodedFileLocation/content"
    if [[ "$etag" != "" ]]
    then
        response=$(curl -s "$secureOption" --write-out '\n%{http_code}' -X PUT "$urlRoot/$uri" --upload-file $inputFile -H 'If-Match: '"$etag"'' -H "Content-Type: application/octet-stream" -H "Accept: application/json" -H "Authorization: Bearer $accessToken") 
    else
        response=$(curl -s "$secureOption" --write-out '\n%{http_code}' -X PUT "$urlRoot/$uri" --upload-file $inputFile -H "Content-Type: application/octet-stream" -H "Accept: application/json" -H "Authorization: Bearer $accessToken") 
    fi
    httpCode=$(echo "$response" | tail -n1)
    responseBody=$(echo "$response" | sed '$d')    
    if [[ "$httpCode" == "200" || "$httpCode" == "201" ]]
    then
        echo "File uploaded successfully."
    else
        echo "File upload failed: $httpCode"
        echo "Response: $responseBody"
    fi
}

#  Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--file)
      inputFile="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--compute-context-name)
      computeContext="$2"
      shift # past argument
      shift # past value
      ;;
    -t|--target-location)
      targetLocation="$2"
      shift # past argument
      shift # past value
      ;;
    --force)
      force="1"
      shift # past argument
      ;;
    -h|--hostname)
      #  the remote host to connect to
      hostname="$2"
      shift # past argument
      shift # past value
      ;;
    -u|--user)
      user="$2"
      shift # past argument
      shift # past value
      ;;
    -p|--password)
      password="$2"
      shift # past argument
      shift # past value
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
. "$thispath/_computeShared.sh"
if [[ "$SAS_CLI_PROFILE" == "" ]]
then
    if [[ "$hostname" == "" || "$user" == "" || "$password" == "" ]]
    then
        echo "ERROR: To authenticate you must either set the SAS_CLI_PROFILE environment variable or the hostname, user and password must be provided."
        exit 22
    fi
else
    echo "Validate Viya CLI configuration"
    validateCLISetup
fi

#  grab the access token and endpoint information from the CLI profile - we'll need it later to issue direct service requests
accessToken=$(getAccessToken)
if [[ $accessToken == "" ]]
then
    echo "ERROR: Unable to obtain access token"
    rc=2
    exit $rc
fi

urlRoot=$(getUrlRoot)
if [[ $urlRoot == "" ]]
then
    echo "ERROR: Unable to obtain SAS endpoint"
    rc=2
    exit $rc
fi

echo "---------------------------------------------------"

if [[ ! -f "$inputFile" ]]
then
    echo "ERROR: The file '$inputFile' does not exist."
    rc=22
    exit $rc
fi

# get the compute context to use
computeContextId=$(getComputeContextId "$computeContext")
if [[ $computeContextId == "" ]]
then
    echo "ERROR: Unable to find compute context '$computeContext'"
    exit 22
fi

# start a compute session
echo "Starting compute session..."
start=$SECONDS
sessionId=$(startComputeSession "$computeContextId")
if [[ "$sessionId" == "" || "$sessionId" == "null" ]]
then
    echo "ERROR: Unable to start compute session in context '$computeContext'"
    exit 22
fi
waitSession $sessionId

# upload the file
echo "Uploading file '$inputFile' to location '$targetLocation'..."
uploadFile "$inputFile" "$targetLocation" "$sessionId"

# terminate the compute session
echo "Terminating compute session..."
terminateComputeSession $sessionId
