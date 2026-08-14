#!/bin/bash

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
   echo ""
   echo "This script is used to analyze content persisted by Viya applications and report on their overall usage."
   echo ""
   echo "Usage:"
   echo ""
   echo "1. Authenticate with an administrative user to the sas-admin or sas-viya CLIs: sas-viya --profile <profile-name> auth login"
   echo "2. Set the SAS_CLI_PROFILE environment variable: export SAS_CLI_PROFILE=<profile-name>"
   echo "3. Perform an analysis on all resources: ./analyzeContentResources.sh"
   echo "4. Perform an analysis of file resources: ./analyzeContentResources.sh --type files --files-show-advanced"
   echo "5. Perform an analysis of job resources: ./analyzeContentResources.sh --type jobs"
   echo ""
   echo "Parameters:"
   echo ""
   echo " -o|--output-directory = The directory to write output files to. Defaults to the current working directory."
   echo " -t|--type = The type of resources to analyze. Defaults to \"all\". Supports a comma delimitted list of the following values:"
   echo "      files: retrieves statistics on file resources managed by the sas-files service"
   echo "      jobs: retrieves statistics on the number of jobs running within the SAS Job Execution service"
   echo "      users: retrieves statistics on the number of users registered in the Identity Provider compared to the users persisted in Viya."
   echo "      transfer: retrieves statistics on persisted transfer packages, used for promoting content between environments."
   echo "      folders: retrieves statistics on the number of folders in the SAS Content tree"   
   echo " --files-show-advanced = Appends additional information to the csv file for each file resource, including the folder path where the file is contained."
   echo " --files-filter-min-size = The minimum file size (in Kb) to filter on. Defaults to 1000 Kb."
   echo " --page-size = Controls the number of records to include in a single page when communicating with the Viya services."
   echo ""
}

function trim {
    local trimmed="$1"

    # Strip leading spaces.
    while [[ $trimmed == ' '* ]]; do
       trimmed="${trimmed## }"
    done
    # Strip trailing spaces.
    while [[ $trimmed == *' ' ]]; do
        trimmed="${trimmed%% }"
    done

    echo "$trimmed"
}

function getFolderPath {
    local uri="$1"

    path=""
    pathOutput="folderpath.json"
    foldersUri="folders/ancestors?childUri=$uri"
    httpCode=$(curl -s -w "%{http_code}" -o "$pathOutput" "$secureOption" "$urlRoot/$foldersUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken")
    if [[ -s "$pathOutput" ]]
    then
        if [[ "$httpCode" == "200" ]]
        then
            while IFS="|" read -r name; do
                path="/${name}${path}"
            done< <(jq -r '.? | .[] | "\(.name)"' $pathOutput)
        fi
        rm $pathOutput
    fi
    echo "$path"
}

function analyzeUsers {

    echo "Analyzing users..."
    uri="identities/users?limit=$pageSize"
    tempOutput="users.json"
    totalNumUsers=0
    pageNumber=0
    declare -A users

    # first fetch the set of active  from the identities service
    while [[ "$NEXT_LINK" != "" || "$pageNumber" == "0" ]]
    do
        curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
        if [[ "$pageNumber" == "0" ]]
        then
            totalNumUsers=`cat $tempOutput | jq -r .count`
            echo "Number of registered users: $totalNumUsers"
        fi

        while IFS="|" read -r id name; do
            users[$id]=$(trim $name)
        done< <(jq -r '.items[] | "\(.id)|\(.name)"' $tempOutput)

        NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $tempOutput`
        uri="$NEXT_LINK"
        pageNumber=$(( pageNumber + 1 ))
    done

    # next compare that to the users (active or inactive) who have logged into the system at least once
    uri="folders/rootFolders?filter=eq(name,'Users')"
    read userRootId memberCount < <(echo $(curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | jq -r '.items[] | select(.type=="userRoot") | .id, .memberCount'))
    if [[ "$userRootId" == "" ]]
    then
        echo "WARNING: Unable to find user root folder."
    else
        echo "Number of user home folders: $memberCount"
        
        userRootId=$(trim $userRootId)
        uri="folders/folders/$userRootId/members?limit=100"
        NEXT_LINK=""
        pageNumber=0
        counter=0
        while [[ "$NEXT_LINK" != "" || "$pageNumber" == "0" ]]
        do
            curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
            while IFS="|" read -r uri name; do
                # is the user registered
                name=$(trim $name)
                userName=`echo ${users[$name]}`
                if [[ "$userName" == "" && "$name" != "sas."* ]]
                then
                    counter=$(( counter + 1 )) 
                    echo "Found unregistered user: $name"
                fi
            done< <(jq -r '.items[] | "\(.uri)|\(.name)"' $tempOutput)

            NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $tempOutput`
            uri="$NEXT_LINK"
            pageNumber=$(( pageNumber + 1 ))         
        done
    fi

    rm $tempOutput
}

function analyzeJobs {
    local tempOutput="jobs.json"
    local pageNumber=0
    local NEXT_LINK=""
    
    local count=0
    local midnight=`date -d 'today 00:00:00' +"%Y-%m-%dT%H:%M:%S.%3NZ"`
    local sunday=`date -d 'last-sunday 00:00:00' +"%Y-%m-%dT%H:%M:%S.%3NZ"`
    
    echo "Analyzing jobs..."

    uri="jobExecution/jobs?filter=eq(state,running)"
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Jobs currently running: $count"

    uri="jobExecution/jobs?filter=gt(creationTimeStamp,'$midnight')"
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Executed jobs today: $count"

    uri="audit/entries?filter=and(eq(action,create),startsWith(uri,'/jobExecution/jobs/'),not(contains(uri,'heartbeat')),gt(timeStamp,'$sunday'))&limit=9999"
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Executed jobs this week: $count"

    uri="jobExecution/jobs?filter=and(eq(state,failed),gt(creationTimeStamp,'$midnight'))"
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Failed jobs today: $count"

    echo "Longest running jobs today:"
    declare -A completedJobs
    declare -A sorted_map
    uri="jobExecution/jobs?filter=gt(creationTimeStamp,'$midnight')&limit=100"

    # iterate through the completed jobs so we can find the ones with the greatest elapsed time
    # note that "elapsedTime" is not a persisted value with the job execution service, so we need to search through them all
    # and sort on this value manually
    while [[ "$NEXT_LINK" != "" || "$pageNumber" == "0" ]]
    do
        curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
        while IFS="|" read -r id elapsedTime; do
            completedJobs["$id"]="$elapsedTime"
        done< <(jq -r '.items[] | "\(.id)|\(.elapsedTime)"' $tempOutput)

        NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $tempOutput`
        uri="$NEXT_LINK"
        pageNumber=$(( pageNumber + 1 ))
    done

    # now that we have the full list of completed jobs from today, sort them based on their elapsed times
    mapfile -t sortedLines < <(
        for key in "${!completedJobs[@]}"; do
            echo "$key ${completedJobs[$key]}"
        done | sort -k2,2nr
    )
    for ((i=0; i<10 && i<${#sortedLines[@]}; i++)); do
        jobId=$(echo "${sortedLines[$i]}" | awk '{print $1}')
        elapsedTime=$(echo "${sortedLines[$i]}" | awk '{print $2}')

        url="$urlRoot/jobExecution/jobs/$jobId"
        read state createdBy name <  <(echo $(curl -s "$secureOption" "$url" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | jq -r '.state, .createdBy, .jobRequest.name | select(. != null) '))
        if [[ "$name" == "" ]]
        then
            name="unknown"
        fi
        seconds=$(awk "BEGIN {print $elapsedTime / 1000}")
        echo "- $name - ${seconds}s ($state, by $createdBy)"        
    done

    # output full details of all recent jobs
    if [[ "$lastRun" == "1" ]]
    then
        echo ""
        echo "Retrieving job details since '$lastRunDate'..."
        pageNumber=0
        NEXT_LINK=""
        detailedJobList="$outputDir/jobs-details-list-$timestamp.csv"
        uri="jobExecution/jobs?filter=and(gt(creationTimeStamp,'$lastRunDate'),not(startsWith(createdBy,'sas.')))&limit=$pageSize"
        echo "\"id\",\"name\",\"user\",\"state\",\"startTime\",\"endTime\",\"elapsedTime\"" > $detailedJobList

        while [[ "$NEXT_LINK" != "" || "$pageNumber" == "0" ]]
        do
            curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
            while IFS="|" read -r id name user state startTime endTime elapsedTime; do

                elapsedTimeSeconds=$(awk "BEGIN {print $elapsedTime / 1000}")
                echo "\"$id\",\"$name\",\"$user\",\"$state\",\"$startTime\",\"$endTime\",\"${elapsedTimeSeconds}s\"" >> "$detailedJobList"

            done< <(jq -r '.items[] | "\(.id)|\(.jobRequest.name)|\(.createdBy)|\(.state)|\(.creationTimeStamp)|\(.endTimeStamp)|\(.elapsedTime)"' $tempOutput)

            NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $tempOutput`
            uri="$NEXT_LINK"
            pageNumber=$(( pageNumber + 1 ))
        done
        echo "Additional details written to: $detailedJobList"
    fi

    echo ""
    echo "Analyzing scheduling details..."

    pageNumber=0
    NEXT_LINK=""
    inactiveJobs=()
    weeklyJobs=()
    dailyJobs=()
    hourlyJobs=()
    minutelyJobs=()
    uri="scheduler/jobs?limit=$pageSize"
    scheduledJobList="$outputDir/scheduled-jobs-list-$timestamp.csv"
    echo "\"jobId\",\"jobName\",\"active\",\"runAs\",\"lastRanDate\",\"lastRanExecutionTime\",\"lastRanStatus\",\"recurrenceType\",\"recurrenceInterval\",\"recurrenceOffset\"" > $scheduledJobList

    while [[ "$NEXT_LINK" != "" || "$pageNumber" == "0" ]]
    do
        curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
        if [[ "$pageNumber" == "0" ]]
        then
            totalJobCount=`cat $tempOutput | jq -r .count`
            echo "Scheduled jobs: $totalJobCount"
            echo "Fetching job history..."
        fi

        while IFS="|" read -r id name runAs active hours minutes type skipCount; do

            if [[ "$active" == "true" ]]
            then
                if [[ "$type" == "weekly" ]]
                then
                    weeklyJobs+=("$id")
                elif [[ "$type" == "daily" ]]
                then
                    dailyJobs+=("$id")
                elif [[ "$type" == "hourly" ]]
                then
                    hourlyJobs+=("$id")
                elif [[ "$type" == "minutely" ]]
                then
                    minutelyJobs+=("$id")
                fi
            else
                inactiveJobs+=("$id")
            fi

            # get the history of each scheduled job so we can see when it last ran
            historyOutput="job-history-$id.json"
            historyUri="scheduler/jobs/$id/history?sortBy=jobFireTimeStamp:descending&limit=1"
            curl -s "$secureOption" "$urlRoot/$historyUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $historyOutput > /dev/null
            IFS=$'\t' read -r lastRanDate lastRanExecutionTime lastRanState < <(
                jq -r '(.items[0] // {}) | [(.jobFireTimeStamp // ""), ((.jobRunTime // 0) * 60), (.jobStatus // "")] | @tsv' "$historyOutput"
            )

            rm "$historyOutput"
            offset="$hours:$minutes"
            echo "\"$id\",\"$name\",\"$active\",\"$runAs\",\"$lastRanDate\",\"${lastRanExecutionTime}s\",\"$lastRanState\",\"$type\",\"$skipCount\",\"$offset\"" >> "$scheduledJobList"

        done< <(jq -r '.items[] | "\(.id)|\(.name)|\(.runAs)|\(.triggers[0].active)|\(.triggers[0].hours)|\(.triggers[0].minutes)|\(.triggers[0].recurrence.type)|\(.triggers[0].recurrence.skipCount)"' $tempOutput)

        NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $tempOutput`
        uri="$NEXT_LINK"
        pageNumber=$(( pageNumber + 1 ))
    done

    echo "Inactive jobs: ${#inactiveJobs[@]}"
    echo "Scheduled to run weekly: ${#weeklyJobs[@]}"
    echo "Scheduled to run daily: ${#dailyJobs[@]}"
    echo "Scheduled to run hourly: ${#hourlyJobs[@]}"
    echo "Scheduled to run minutely: ${#minutelyJobs[@]}"
    echo "Additional details written to: $scheduledJobList"

    echo ""
    echo "Analyzing batch jobs..."

    uri="audit/entries?filter=and(eq(action,create),startsWith(uri,'/batch/jobs/'),gt(timeStamp,'$midnight'))&limit=9999"
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Submitted batch jobs today: $count"

    uri="audit/entries?filter=and(eq(action,create),startsWith(uri,'/batch/jobs/'),gt(timeStamp,'$sunday'))&limit=9999"
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Submitted batch jobs this week: $count"

    rm $tempOutput
}

function analyzeTransferPackages {
    uri="transfer/packages?limit=10"
    tempOutput="transfer.json"
    count=0
    
    echo "Analyzing transfer packages..."
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Count: $count"
    rm $tempOutput
}

function analyzeFolders {
    uri="folders/folders?limit=10"
    tempOutput="folders.json"
    count=0
    
    echo "Analyzing folders..."
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Count: $count"
    rm $tempOutput
}

function analyzeFiles {
    uri="files/files?limit=10"
    tempOutput="files.json"
    count=0
    
    echo "Analyzing files..."
    curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
    count=`cat $tempOutput | jq -r .count`
    echo "Count: $count"

    if [[ "$filesMinSize" == "" ]]
    then
        filesMinSize=1000000 # default to filter on files greater than 1mb
    fi
    filesMaxSize=0
    if [[ $filesMaxSize == "0" ]]
    then
        filter="gt(size,$filesMinSize)"
    else
        filter="and(lt(size,$filesMaxSize),gt(size,$filesMinSize))"
    fi

    uri="files/files?filter=$filter&limit=$pageSize&sortBy=size:descending"

    largeFileCount=0
    totalFileCount=0
    totalFileSize=0
    local pageNumber=0
    local NEXT_LINK=""
    fileList="$outputDir/files-list.csv"
    echo "\"id\",\"name\",\"size\",\"createdBy\",\"createdDate\",\"parent\",\"folder\"" > $fileList

    while [[ "$NEXT_LINK" != "" || "$pageNumber" == "0" ]]
    do
        curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempOutput > /dev/null
        if [[ "$pageNumber" == "0" ]]
        then
            totalFileCount=`cat $tempOutput | jq -r .count`
            echo "Largest files:"
        fi

        while IFS="|" read -r id name size createdBy creationTimeStamp parentUri; do
            parentValue=$(trim $parentUri)
            if [[ "$parentValue" == "null" ]]
            then
                parentValue="none"
            fi

            totalFileSize=$(( totalFileSize + $size ))
            largeFileCount=$(( largeFileCount + 1 ))
            if [ $largeFileCount -lt 20 ]
            then
                echo "- $name ($(( size / 1000)) KB)"
            fi

            uri="/files/files/$id"
            if [[ "$filesShowAdvanced" == "1" ]]
            then
                folderPath=`getFolderPath "$uri"`
                if [[ "$folderPath" == "" ]]
                then
                    folderPath="none"
                fi
            else
                folderPath="N/A"
            fi

            echo "\"$id\",\"$name\",\"$(( size / 1000))\",\"$createdBy\",\"$creationTimeStamp\",\"$parentValue\",\"$folderPath\"" >> "$fileList"
        done< <(jq -r '.items[] | "\(.id)|\(.name)|\(.size)|\(.createdBy)|\(.creationTimeStamp)|\(.parentUri)"' $tempOutput)

        NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $tempOutput`
        uri="$NEXT_LINK"
        pageNumber=$(( pageNumber + 1 ))
    done

    echo ""
    echo "Number of files over $(( filesMinSize / 1000)) KB: $totalFileCount"
    echo "Subsetted file size: $(( totalFileSize / 1000 )) KB"
    echo "Additional details written to: $fileList"
    rm $tempOutput
}

#################################################################
#  Main
#################################################################

pageSize=100
timestamp=`date +%Y%m%d%H%M%S%N`
outputDir="$PWD"

#  Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --files-filter-min-size)
      filesMinSize="$2"
      shift # past argument
      shift # past value
      ;;
    --files-show-advanced)
      filesShowAdvanced="1"
      shift # past argument
      ;;      
    --page-size)
      pageSize="$2"
      shift # past argument
      shift # past value
      ;;
    --max-pages)
      maxPages="$2"
      shift # past argument
      shift # past value
      ;;
    --last-run)
      lastRun="1"
      shift # past argument
      ;;
    -t|--type)
      type="$2"
      shift # past argument
      shift # past value
      ;;
    -k|--insecure)
      secureOption="-k"
      shift # past argument
      ;;
    -o|--output-directory)
      outputDir="$2"
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
. "$thispath/../common/_auditFunctions.sh"
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

# if requested, capture the last run date
if [[ "$lastRun" == "1" ]]
then
    lastRunFile="$outputDir/lastRun.txt"
    if [[ -f "$lastRunFile" ]]
    then
        # capture the last run date and set a new value
        lastRunDate=`cat "$lastRunFile"`
        echo `date +%Y-%m-%dT%H:%M:%S.%3NZ` > "$lastRunFile"

    else
        # could not find the last run value, assume this is the first attempt and use midnight as the default
        lastRunDate=`date -d 'today 00:00:00' +"%Y-%m-%dT%H:%M:%S.%3NZ"`
        echo "$lastRunDate" > "$lastRunFile"
    fi
fi

echo "---------------------------------------------------"
echo ""

if [[ "$type" == "" ]]
then
    type="all"
fi

if [[ "$type" == "all" || "$type" == *"files"* ]]
then
    analyzeFiles
    printSeparator
fi
if [[ "$type" == "all" || "$type" == *"transfer"* ]]
then
    analyzeTransferPackages
    printSeparator
fi
if [[ "$type" == "all" || "$type" == *"users"* ]]
then
    analyzeUsers
    printSeparator
fi
if [[ "$type" == "all" || "$type" == *"folders"* ]]
then
    analyzeFolders
    printSeparator
fi
if [[ "$type" == "all" || "$type" == *"jobs"* ]]
then
    analyzeJobs
    printSeparator
fi