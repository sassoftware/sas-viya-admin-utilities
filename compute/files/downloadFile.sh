#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
    echo ""
    echo "This script is used to download files from a location on the SAS Server to your local machine."
    echo ""
    echo "Usage:"
    echo ""
    echo "1. Authenticate by either passing in the hostname/user/password values directly to this script, or by using the sas-viya CLI as follows:"
    echo "   sas-viya --profile <profile-name> auth login"
    echo "   export SAS_CLI_PROFILE=<profile-name>"
    echo ""
    echo "2. Download a file: ./downloadFile.sh --compute-context-name {compute-context} --file /remote/directory/myfile.txt --out /local/directory"
    echo ""
    echo "Parameters:"
    echo ""
    echo " -h|--hostname = The hostname of the SAS server."
    echo " -u|--user = The user name to authenticate as."
    echo " -p|--password = The password for the user."
    echo " -f|--file = The input file to download."
    echo " -o|--out = The local directory to download the file to. Defaults to the current working directory."
    echo " -c|--compute-context-name = The name of the compute context to use."
    echo " -k|--insecure = If specified, will skip SSL certificate validation."
    echo ""
}

function downloadFile {
    local file="$1"
    local outputLocation="$2"
    local sessionId="$3"
    local encodedFileLocation="${file//\//~fs~}"
    local fileName=`basename "$file"`

    # check to see if the file exists
    local uri="compute/sessions/$sessionId/files/$encodedFileLocation"
    response=$(curl -s "$secureOption" "$urlRoot/$uri" --write-out '\n%{http_code}' --output /dev/null -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken" -D $headers)
    response=`echo $response | tail -n1`
    if [[ "$response" == "404" ]]
    then
        echo "The file does not exist."
        return
    fi
    uri="compute/sessions/$sessionId/files/$encodedFileLocation/content"
    response=$(curl -s "$secureOption" --write-out '\n%{http_code}' --output $out/$fileName "$urlRoot/$uri" -H "Accept: application/octet-stream" -H "Authorization: Bearer $accessToken") 
    httpCode=$(echo "$response" | tail -n1)
    responseBody=$(echo "$response" | sed '$d')    
    if [[ "$httpCode" == "200" || "$httpCode" == "201" ]]
    then
        echo "File downloaded successfully."
    else
        echo "File download failed: $httpCode"
        echo "Response: $responseBody"
    fi
}

#  Parse arguments
out=$PWD
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--out)
      out="$2"
      shift # past argument
      shift # past value
      ;;
    -f|--file)
      file="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--compute-context-name)
      computeContext="$2"
      shift # past argument
      shift # past value
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

if [[ ! -d "$out" ]]
then
    echo "ERROR: The directory '$out' does not exist."
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

# download the file
echo "Downloading file '$file' to location '$out'..."
downloadFile "$file" "$out" "$sessionId"

# terminate the compute session
echo "Terminating compute session..."
terminateComputeSession $sessionId
