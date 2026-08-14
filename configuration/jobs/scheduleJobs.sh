#!/bin/bash 

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function createJob {
    jobNumber="$1"
    local jobName="Scheduled_Job_$jobNumber"
    
    local tempJobOutput="job_output_$jobNumber.json"
#     local jobInput=$(cat <<EOF
# {
#   "version": 3,
#   "name": "$jobName",
#   "jobDefinition": {
#     "version": 1,
#     "name": "$jobName",
#     "type": "Compute",
#     "code": "/* A simple Hello World SAS program */\r\n\r\n/* Print Hello World */\r\ndata _null_;\r\n   put \"Hello, World !\";\r\nrun;\r\n\r\n/* Get license information */\r\nproc setinit noalias;\r\nrun;\r\n\r\n/* Output total memory size default value */\r\nproc options option=MEMSIZE value;\r\nrun;\r\n\r\n/* Output total sort size default value */\r\nproc options option=SORTSIZE value;\r\nrun;\r\n\r\n/* Output number of threads default value */\r\nproc options option=CPUCOUNT value;\r\nrun;",
#     "parameters": [
#       {
#         "version": 1,
#         "name": "_contextName",
#         "defaultValue": "SAS Job Execution compute context",
#         "label": "Context Name",
#         "required": false,
#         "type": "CHARACTER"
#       }
#     ]
#   },
#   "arguments": {
#     "_contextName": "SAS Job Execution compute context"
#   }
# }
# EOF
# )

    local jobInput=$(cat <<EOF
{
  "version": 3,
  "name": "$jobName",
  "jobDefinitionUri": "/jobDefinitions/definitions/$jobDefId",
  "arguments": {
    "_contextName": "SAS Job Execution compute context"
  }
}
EOF
)

    local jobUri="jobExecution/jobRequests"
    curl --silent "$secureOption" "$urlRoot/$jobUri" -X POST --data-raw "$jobInput" -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempJobOutput > /dev/null
    jobId=`jq -r '.id' $tempJobOutput`
    rm $tempJobOutput
    echo "$jobId"
}

function scheduleJob {
    local jobId="$1"
    local jobName="Scheduled_Job_$jobId"    
    local tempJobOutput="scheduled_job_output_$jobId.json"
    local jobInput=$(cat <<EOF
{
  "name": "$jobName",
  "description": "",
  "request": {
    "uri": "/jobExecution/jobRequests/$jobId/jobs",
    "method": "POST",
    "headers": {
      "Accept": ["application/vnd.sas.job.execution.job+json"]
    }
  },
  "triggers": [
    {
      "active": true,
      "applicationId": "SAS Environment Manager",
      "name": "New Trigger",
      "hours": "00",
      "minutes": "$scheduledMinute",
      "order": 0,
      "type": "timeevent",
      "timezone": "America/New_York",
      "recurrence": {
        "type": "hourly",
        "startDate": "2026-01-22",
        "skipCount": 1,
        "dayOfMonth": 1,
        "daysOfWeek": []
      }
    }
  ]
}
EOF
)

    local schedulerUri="scheduler/jobs"
    curl --silent "$secureOption" "$urlRoot/$schedulerUri" -X POST --data-raw "$jobInput" -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $tempJobOutput > /dev/null
    jobId=`jq -r '.id' $tempJobOutput`
    rm $tempJobOutput
    echo "$jobId"
}

function deleteJob {
    local jobRequestId="$1"
    local jobUri="jobExecution/jobRequests/$jobRequestId"
    response=$(curl --silent "$secureOption" --write-out '\n%{http_code}' --output /dev/null "$urlRoot/$jobUri" -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $accessToken")
    response=`echo $response | tail -n1`
    if [[ "$response" == "204" ]]
    then
        echo "  Delete successful"
    else
        echo "  Delete failed: $response"
    fi
}

function unscheduleJob {
    local jobId="$1"
    local schedulerUri="scheduler/jobs/$jobId"
    response=$(curl --silent "$secureOption" --write-out '\n%{http_code}' --output /dev/null "$urlRoot/$schedulerUri" -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $accessToken")
    response=`echo $response | tail -n1`
    if [[ "$response" == "204" ]]
    then
        echo "  Unschedule successful"
    else
        echo "  Unschedule failed: $response"
    fi
}

#################################################################
#  Main
#################################################################

outputDir="$PWD"
secureOption=""

# create, enable, disable, delete, update schedule

#  Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--action)
      action="$2"
      shift # past argument
      shift # past value
      ;;
    -j|--job-file)
      jobFile="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--job-count)
      jobCount="$2"
      shift # past argument
      shift # past value
      ;;
    --job-def-id)
      jobDefId="$2"
      shift # past argument
      shift # past value
      ;;
    --scheduled-minute)
      scheduledMinute="$2"
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


if [[ "$action" == "create" || "$action" == "create,"* ]]
then
    echo "Creating jobs..."
    if [[ "$jobCount" == "" ]]
    then
        jobCount=1
    fi

    if [[ "$scheduledMinute" == "" ]]
    then
        scheduledMinute="00"
    fi

    if [[ "$jobFile" == "" ]]
    then
        jobFile="$outputDir/scheduled_jobs_$(date +%Y%m%d_%H%M%S).csv"
    fi
    if [[ -f "$jobFile" ]]
    then
        rm "$jobFile"
    fi

    touch "$jobFile"
    for ((i=1; i<=$jobCount; i++)); do
        echo "Creating job: $i"
        jobRequestId=$(createJob "$i")
        if [[ "$jobRequestId" != "" && "$jobRequestId" != "null" ]]
        then
            echo "$jobRequestId," >> $jobFile
            echo "  Creation successful"
        else
            echo "  ERROR: Unable to create job"
        fi
    done
fi

if [[ "$action" == "schedule" || "$action" == *",schedule"* ]]
then
    echo "Scheduling jobs..."
    tempFile="$outputDir/$(basename "$jobFile").tmp"
    > "$tempFile"
    count=0
    while IFS=',' read -r jobRequestId; do
        ((count++))
        echo "Scheduling job ($count): $jobRequestId"
        jobId=$(scheduleJob "$jobRequestId")
        if [[ "$jobId" != "" && "$jobId" != "null" ]]
        then
            echo "$jobRequestId,$jobId" >> "$tempFile"
            echo "  Schedule successful"
        else
            echo "  ERROR: Unable to schedule job $jobRequestId"
            echo "$jobRequestId," >> "$tempFile"
        fi
    done < "$jobFile"
    mv "$tempFile" "$jobFile"
fi

if [[ "$action" == "unschedule" || "$action" == "unschedule,"* ]]
then
    echo "Unscheduling jobs..."
    count=0
    while IFS=',' read -r jobRequestId scheduledJobId; do
        ((count++))
        if [[ "$jobRequestId" != "" ]]; then
            echo "Deleting job schedule ($count): $scheduledJobId"
            unscheduleJob "$scheduledJobId"
        fi
    done < "$jobFile"
fi

if [[ "$action" == "delete" || "$action" == *",delete" ]]
then
    echo "Deleting jobs..."
    count=0
    while IFS=',' read -r jobRequestId scheduledJobId; do
        ((count++))
        if [[ "$jobRequestId" != "" ]]; then
            echo "Deleting job request ($count): $jobRequestId"
            deleteJob "$jobRequestId"
        fi
    done < "$jobFile"
fi

# Create and Schedule
# ./jobs/scheduleJobs.sh -k --action create,schedule --job-file scheduled_jobs_1.csv --job-def-id 1566b601-4802-41d8-bb23-eae44d93a7c4 --job-count 100 --scheduled-minute 20

# Unschedule and Delete
# ./jobs/scheduleJobs.sh -k --action unschedule,delete --job-file scheduled_jobs_1.csv

# Unschedule
# ./jobs/scheduleJobs.sh -k --action unschedule --job-file scheduled_jobs_1.csv

# Schedule 
# ./jobs/scheduleJobs.sh -k --action create,schedule --job-file scheduled_jobs_1.csv --scheduled-minute 20