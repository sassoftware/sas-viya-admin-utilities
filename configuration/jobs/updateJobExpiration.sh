#!/bin/bash 

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
   echo ""
   echo "This script is used to update the expiration timestamp for any completed jobs that have been submitted"
   echo "through the SAS Job Execution service (sas-job-execution). By default, jobs created when using SAS Studio"
   echo "(such as background submissions or scheduled jobs) expire after 3 days. This script can be used to modify that"
   echo "expiration period, either by decreasing or increasing the number of days before expiration."
   echo ""
   echo "Usage:"
   echo ""
   echo "1. Authenticate with an administrative user to the sas-admin or sas-viya CLIs: sas-admin --profile <profile-name> auth login"
   echo "2. Set the SAS_CLI_PROFILE environment variable: export SAS_CLI_PROFILE=<profile-name>"
   echo "3. Change the expiration value to 1 day: ./updateJobExpiration.sh --filter-userid <userid> --expiration-in-days 1 --commit"
   echo ""
   echo "Parameters:"
   echo ""
   echo " -c|--commit = Persists any modifications for the jobs. Without this option, the script performs a dry-run by default."
   echo " -e|--expiration-in-days = The number of days to set the expiration timestamp to (default from SAS Studio is 3 days)"
   echo " -i|--filter-userid = (Optional) The userid who owns the jobs. If not set, all jobs associated with all users will be processed."
   echo " -k|--insecure = Ignore using certificates when issuing commands"
   echo ""
}

function updateJobExpiration {
    local id="$1"
    local expiry="$2"
    local updatedExpiry=$(TZ="GMT" date +"%Y-%m-%dT%H:%M:%S.%3NZ" -d "$expiry +$expDays days")
    echo "  New expiration date: $updatedExpiry"
    if [[ "$commit" == "1" ]]
    then
        # on some systems, curl is returning the output in the form of "000{response-body}{status-code}", where the response code itself is buried
        # in the same line as the body. to work around that, make sure we're printing a new line in between
        local uri="jobExecution/jobs/$id/expirationTimeStamp?value=$updatedExpiry"
        statusCode=`curl -s "$secureOption" --write-out '\n%{http_code}' --output /dev/null "$urlRoot/$uri" -X PUT -H "Accept: text/plain" -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken"`           
        statusCode=`echo $statusCode | tail -n1`
        if [[ "$statusCode" == "200" ]]
        then
            echo "  Update succeeded."
            updateCount=$(( updateCount + 1 ))
        else
            echo "  Update failed. Reason: $statusCode"
        fi
    fi
}

#################################################################
#  Main
#################################################################

outputDir="$PWD"
pageSize=50
sortOrder="ascending"
secureOption=""

#  Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--commit)
      commit="1"
      shift # past argument
      ;;
    -e|--expiration-in-days)
      expDays="$2"
      shift # past argument
      shift # past value
      ;;
    -k|--insecure)
      secureOption="-k"
      shift # past argument
      ;;
    --last-run)
      lastRun="1"
      shift # past argument
      ;;
    -o|--output-directory)
      outputDir="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--filter-userid)
      creator="$2"
      shift # past argument
      shift # past value
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

if [[ ! -d "$outputDir" ]]
then
    echo "ERROR: The output directory '$outputDir' does not exist."
    exit 22
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

if [[ $expDays -lt 1 ]]
then
    echo "ERROR: A value of 1 (or more) must be specified for the expiration-in-days argument."
    rc=2
    exit $rc
fi

echo "---------------------------------------------------"
if [[ "$commit" != "1" ]]
then
    echo "NOTE: Performing a dry-run. Use the --commit flag to persist any changes."
fi
echo ""

# build the proper URI and filter needed to fetch the jobs
updateCount=0
currentTime=$(date +"%s")
filter="and(eq(state,completed)"

# fetch jobs associated with particular user
if [[ "$creator" != "" ]]
then
    echo "Retrieving job details for user '$creator'..."
	filter+=",eq(createdBy,$creator)"
else
    # exclude system generated jobs
    filter+=",not(startsWith(createdBy,'sas.'))"
fi

# fetch the jobs created recently (since the last time this process was executed)
if [[ "$lastRun" == "1" ]]
then
    lastRunFile="$outputDir/lastRun.txt"
    if [[ -f "$lastRunFile" ]]
    then
        # capture the last run date and set a new value
        lastRunDate=`cat "$lastRunFile"`
        echo $(TZ="GMT" date +%Y-%m-%dT%H:%M:%S.%3NZ) > "$lastRunFile"

    else
        # could not find the last run value, assume this is the first attempt and use midnight as the default
        lastRunDate=$(TZ="GMT" date -d 'today 00:00:00' +"%Y-%m-%dT%H:%M:%S.%3NZ")
        echo "$lastRunDate" > "$lastRunFile"
    fi

	echo "Retrieving job details since '$lastRunDate'..."
	filter+=",gt(creationTimeStamp,'$lastRunDate')"
fi

filter+=")"
jobUri="/jobExecution/jobs?limit=$pageSize&sortBy=creationTimeStamp:$sortOrder&filter=$filter"

tempOutput="$outputDir/jobs.json"
pageNumber=1
echo "Retrieving list of jobs"
while [[ "$NEXT_LINK" != "" || "$pageNumber" == "1" ]]
do
    curl -s -k "$urlRoot/$jobUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    if [[ "$pageNumber" == "1" ]]
    then
        totalNumJobs=`cat $tempOutput | jq -r .count`
        echo "Total number of jobs found: $totalNumJobs"
    else
        echo "Processing page #$pageNumber"
    fi

    while IFS="|" read -r id name endTimeStamp expirationTimeStamp; do

        runDate=$(TZ="GMT" date -d "$endTimeStamp" +"%Y%m%d")
        expDate=$(TZ="GMT" date -d "$expirationTimeStamp" +"%Y%m%d")
        dateDiff=$((expDate - runDate))        
        if [[ "$dateDiff" == 3 ]]
        then
            echo ""
            echo "Processing job '$id'."
            echo "  Current expiration date: $expirationTimeStamp"

            # make sure the expiration period hasn't passed
            fullExpDate=$(date -d "${expirationTimeStamp}" +"%s")
            if [ $fullExpDate -ge $currentTime ];
            then
                updateJobExpiration "$id" "$endTimeStamp"
            else
                echo "  Skipping update. Expiration date is before current date."
            fi
        fi
    done< <(jq -r '.items[] | "\(.id)|\(.name)|\(.endTimeStamp)|\(.expirationTimeStamp)"' $tempOutput)

    NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $tempOutput`
    jobUri="$NEXT_LINK"
    pageNumber=$(( pageNumber + 1 ))
    rm $tempOutput

    break
done
echo ""
echo "Number of jobs updated: $updateCount"
