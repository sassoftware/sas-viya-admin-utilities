#!/bin/bash 

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`
thisScript=`basename "$0"`

function showHelp {
   echo ""
   echo "This script is used to retrieve compute session activity on a system within a specific time period. Use the --details option"
   echo "to include detailed information about each compute session, as well as peak concurrency events."
   echo ""
   echo "Usage:"
   echo ""
   echo "1. Authenticate with an administrative user to the sas-viya CLI: sas-viya --profile <profile-name> auth login"
   echo "2. Set the SAS_CLI_PROFILE environment variable: export SAS_CLI_PROFILE=<profile-name>"
   echo "3. Fetch the list of compute sessions with current active sessions: ./analyzeComputeActivity.sh --active"
   echo "4. Fetch the list of distinct compute sessions from today: ./analyzeComputeActivity.sh --today"
   echo "5. Fetch the list of distinct compute sessions since the beginning of this week: ./analyzeComputeActivity.sh --week"
   echo "6. Fetch the list of distinct compute sessions since January 1st, 2025: ./analyzeComputeActivity.sh --since 2025-01-01 00:00:00"
   echo "7. Fetch the complete list of compute sessions from today: ./analyzeComputeActivity.sh --today --details"
   
   echo ""
   echo "Parameters:"
   echo ""
   echo " -o|--output-directory = The directory to write output files to. Defaults to the current working directory."
   echo " -a|--active = Displays the current active sessions."
   echo " -t|--today = Displays the compute sessions since the beginning of the current day."
   echo " -w|--week = Displays the compute sessions since the beginning of the current week."
   echo " -l|--all = Displays the complete list of compute sessions.  Note the number of days surfaced here depends on how long the Viya audit service is configured to retain activity records for.  Depending on the number of records this may take a while to load."
   echo " -s|--since = Displays the compute sessions since the specified date.  The date must be in the format of 'YYYY-mm-dd HH:MM:SS'."
   echo " -b|--before = Displays the compute sessions before the specified date.  The date must be in the format of 'YYYY-mm-dd HH:MM:SS'."
   echo " -d|--details = Includes a detailed report of unique compute session attempts."
   echo " --local-time = Converts any date/time values to your local time zone."
   echo " --page-size = Controls the number of records to include in a single page when communicating with the Viya audit service."
   echo ""
}

function fetchSessionLogoff {
    local sessionId="$1"
    filter="and(eq(type,resource),eq(objectType,ComputeSession),eq(state,success),eq(action,delete),eq(objectName,'$sessionId'))"
    auditUri="audit/activities?limit=$pageSize&start=$start&sortBy=timeStamp:ascending&filter=$filter"

    # capture the timestamp for when the user's session ended
    sessionEndOutput="logoff-$sessionId.json"
    curl -s $secureOption "$urlRoot/$auditUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $sessionEndOutput > /dev/null    
    sessionEndDate=`cat $sessionEndOutput | jq -r '.items[0].timeStamp'`
    rm "$sessionEndOutput"
    echo "$sessionEndDate"
}

function fetchAuditRecordsByDate {
    #verbose="1"

    local sinceDate="$1"
    local beforeDate="$2"
    if [[ "$verbose" == "1" ]]
    then
        echo "Fetching list of compute sessions starting from '$sinceDate'"
    fi

    declare -A sessions
    auditOutput="audit-compute-activity.json"

    if [[ "$showDetails" == "1" ]]
    then
        declare -a concurrencyEvents
        declare -a createdSessions
    fi

    filter="and(eq(type,resource),eq(objectType,ComputeSession),eq(state,success),eq(action,create),gt(timeStamp,'$sinceDate')"
    if [[ "$beforeDate" != "" ]]
    then
        filter+=",lt(timeStamp,'$beforeDate')"
    fi
    filter+=")"

    pageNumber=1
    while [[ "$NEXT_LINK" != "" || "$pageNumber" == "1" ]]
    do
        submitActivitiesRequest "$filter" "$auditOutput" "$pageNumber"
        if [[ "$pageNumber" == "1" ]]
        then
            totalNumRequests=`cat $auditOutput | jq -r .count`
            if [[ "$totalNumRequests" == "null" || "$totalNumRequests" == "" ]]
            then
                totalNumRequests="unknown"
            fi
            if [[ "$verbose" == "1" ]]
            then
                echo "Total number of requests found: $totalNumRequests"
            fi
        else
            if [[ "$verbose" == "1" ]]
            then
                echo "Processing page #$pageNumber"
            fi
        fi

        while IFS="|" read -r user action timeStamp objectName; do
            key="${user}"
            if [[ "$verbose" == "1" ]]
            then
                echo "Found session for '$user': $timeStamp"
            fi

            if [[ "$showDetails" == "1" ]]
            then
                # record that this session was created in our window
                createdSessions+=("$objectName")
                
                # capture how long the session lasted for
                sessionStartTime="$timeStamp"
                sessionEndDate=`fetchSessionLogoff "$objectName"`
                if [[ "$sessionEndDate" != "" && "$sessionEndDate" != "null" ]]
                then
                    sessionEndTime="$sessionEndDate"
                    sessionLength=`calculateSessionLength $sessionStartTime $sessionEndTime`
                else
                    # the session hasn't completed yet - use the current time
                    sessionEndTime=`date +%Y-%m-%dT%H:%M:%S.%3N`
                    sessionLength=`calculateSessionLength $sessionStartTime $sessionEndTime`
                    sessionLength="$sessionLength+"
                fi

                if [[ "$showDetails" == "1" ]]
                then
                    concurrencyEvents+=("$sessionStartTime|1")
                    concurrencyEvents+=("$sessionEndTime|-1")
                fi

                displayStart="$sessionStartTime"
                if [[ "$localTime" == "1" ]]
                then
                    displayStart=`formatDate "$sessionStartTime"`
                fi

                echo "$user at $displayStart ($sessionLength minutes)"
            else
                counter=`echo ${sessions[$key]}`
                if [[ "$counter" == "" ]]
                then
                    let counter=1
                    sessions["$key"]="$counter"
                else
                    sessions["$key"]=$((counter+1))
                fi
            fi
        done< <(jq -r '.items[] | "\(.user)|\(.action)|\(.timeStamp)|\(.objectName)"' $auditOutput)

        NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $auditOutput`
        pageNumber=$(( pageNumber + 1 ))
    done
    rm $auditOutput

    if [[ "$showDetails" != "1" ]]
    then
        echo "Number of distinct users: ${#sessions[@]}"
        echo "Total number of compute sessions:"
        for k in "${!sessions[@]}"; do
            echo "${sessions[$k]} - $k"
        done | sort -rn -k1
    else
        peak=0
        current=0
        peakTime=""

        if [[ ${#concurrencyEvents[@]} -gt 0 ]]
        then
            # find the first CREATE event (delta=+1) to establish baseline
            firstCreateTime=""
            while IFS='|' read -r ts delta; do
                if [[ "$delta" == "1" ]]
                then
                    firstCreateTime="$ts"
                    break
                fi
            done < <(printf '%s\n' "${concurrencyEvents[@]}" | sort -t'|' -k1,1 -k2,2n)

            # calculate peak, ignoring orphaned deletes before first create
            while IFS='|' read -r ts delta; do
                # skip delete events that occur before our first create (orphaned deletes)
                if [[ "$delta" == "-1" && "$ts" < "$firstCreateTime" ]]
                then
                    continue
                fi
                current=$((current + delta))
                if [[ $current -gt $peak ]]
                then
                    peak=$current
                    peakTime="$ts"
                fi
                if [[ $current -eq $peak ]]
                then
                    peakTime="$ts"
                fi
            done < <(printf '%s\n' "${concurrencyEvents[@]}" | sort -t'|' -k1,1 -k2,2n)

            # ensure baseline of 1 when any session events exist
            if [[ $peak -lt 1 ]]
            then
                peak=1
                peakTime="$(printf '%s\n' "${concurrencyEvents[@]}" | sort -t'|' -k1,1 | tail -n1 | cut -d'|' -f1)"
            fi
        fi

        if [[ "$verbose" == "1" ]]
        then
            echo "DEBUG: concurrency events=${#concurrencyEvents[@]}, computed peak=$peak, peakTime=$peakTime"
            echo "DEBUG: event list (sorted):"
            printf '%s\n' "${concurrencyEvents[@]}" | sort -t'|' -k1,1 -k2,2n
        fi

        printSeparator
        if [[ "$peak" -gt 0 ]]
        then
            peakDisplay="$peakTime"
            if [[ "$localTime" == "1" ]]
            then
                peakDisplay=`formatDate "$peakTime"`
            fi
            echo "Peak concurrent compute sessions: $peak (at $peakDisplay)"
        elif [[ "$totalNumRequests" == "0" ]]
        then
            # no one has logged in during this time period
            echo "Peak concurrent compute sessions: 0"
        else
            # users have logged in, but we've never had more than 1 concurrent session at any point in time
            echo "Peak concurrent compute sessions: 1"
        fi
    fi
}

# fetch all available audit records
function fetchAllComputeSessions {
    echo ""
    echo "All-time compute activity..."
    # pick an arbitrary date in the past
    sinceDate=`date -d '2017-01-01 00:00:00' +"%Y-%m-%dT%H:%M:%S.%3NZ"`
    fetchAuditRecordsByDate "$sinceDate"
}

# fetch the list of successful audit records since the specified date
function fetchComputeSessionsCustomDate {
    echo ""

    if [[ "$since" != "" ]]
    then
        echo "Compute activity since '$since'..."
        sinceDate=$(date -d "${since}" +"%Y-%m-%dT%H:%M:%S.%3NZ")
    fi

    if [[ "$before" != "" ]]
    then
        echo "Compute activity before '$before'..."
        beforeDate=$(date -d "${before}" +"%Y-%m-%dT%H:%M:%S.%3NZ")
    fi

    fetchAuditRecordsByDate "$sinceDate" "$beforeDate"
}

# fetch the list of successful audit records from this week
function fetchComputeSessionsFromThisWeek {
    echo ""
    echo "Compute activity from this week..."
    sunday=`date -d 'last-sunday 00:00:00' +"%Y-%m-%dT%H:%M:%S.%3NZ"`
    fetchAuditRecordsByDate "$sunday"
}

# fetch the list of successful audit records from today only
function fetchComputeSessionsFromToday {
    echo ""
    echo "Compute activity from today..."
    midnight=`date -d 'today 00:00:00' +"%Y-%m-%dT%H:%M:%S.%3NZ"`
    fetchAuditRecordsByDate "$midnight"
}

# Retrieves the list of users who have active sessions on the system
# To fetch this information, we need to first look for all of the logon (or 'create') records, and then 
# compare that to the list of records corresponding to destroyed sessions (or 'delete' records).  To do this we need
# to track not only the username, but also the session signature.
function fetchActiveComputeSessions {

    auditOutput="authentication.json"

    declare -A sessions
    users=()

    # get the total number of logon/logout requests
    pageNumber=1
    startDate=`date -d 'today 00:00:00' +"%Y-%m-%dT%H:%M:%S.%3NZ"`
    filter="and(eq(type,security),eq(state,success),or(eq(action,create),eq(action,delete)),gt(timeStamp,$startDate))"
    if [[ "$verbose" == "1" ]]
    then
        echo "Fetching list of active sessions starting from '$date'"
    fi

    while [[ "$NEXT_LINK" != "" || "$pageNumber" == "1" ]]
    do
        submitActivitiesRequest "$filter" "$auditOutput" "$pageNumber"
        if [[ "$pageNumber" == "1" ]]
        then
            totalNumRequests=`cat $auditOutput | jq -r .count`
            if [[ "$totalNumRequests" == "null" ]]
            then
                totalNumRequests="unknown"
            fi
            if [[ "$verbose" == "1" ]]
            then
                echo "Total number of requests found: $totalNumRequests"
            fi
        else
            if [[ "$verbose" == "1" ]]
            then
                echo "Processing page #$pageNumber"
            fi
        fi

        while IFS="|" read -r user action timeStamp session; do
            key="${user}#${session}"
            if [[ ! "$users[*]" =~ "$user" ]]
            then
                users+=( "$user" )
            fi

            if [[ "$action" == "create" ]]
            then
                if [[ "$verbose" == "1" ]]
                then
                    echo "Session authenticated: '$user' ($session) at $timeStamp"
                fi
                sessions["$key"]="$timeStamp"
            elif [[ "$action" == "delete" ]]
            then
                if [[ "$verbose" == "1" ]]
                then
                    echo "Session destroyed: '$user' ($session) at $timeStamp"
                fi
                userSession=`echo ${sessions[$key]}`

                if [[ "$timeStamp" > "$userSession" ]]
                then
                    unset sessions[$key]
                fi
            fi
        done< <(jq -r '.items[] | "\(.user)|\(.action)|\(.timeStamp)|\(.properties.sessionSignature)"' $auditOutput)

        NEXT_LINK=`jq -r '.? | .links[] | select(.rel=="next") | .uri' $auditOutput`
        pageNumber=$(( pageNumber + 1 ))
    done

    # now calculate the active users
    echo ""
    echo "Current user activity..."
    echo "Total number of distinct active users: ${#sessions[@]}"

    for key in "${!sessions[@]}"; do
         username=`echo $key | cut -d "#" -f 1`

         timeStamp="${sessions[$key]}"
         if [[ "$localTime" == "1" ]]
         then
             timeStamp=`formatDate "$timeStamp"`
         fi
         echo "$username at $timeStamp"
    done

    rm $auditOutput
}


#################################################################
#  Main
#################################################################

out="$PWD"
pageSize=100
sortOrder="descending"

active="0"
today="0"
week="0"
all="0"
since=""
verbose="0"
localTime="0"
secureOption=""

#  Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--active)
      active="1"
      shift # past argument
      ;;
    -t|--today)
      today="1"
      shift # past argument
      ;;
    -w|--week)
      week="1"
      shift # past argument
      ;;
    -l|--all)
      all="1"
      shift # past argument
      ;;
    -s|--since)
      since="$2"
      shift # past argument
      shift # past value
      ;;
    -b|--before)
      before="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output-directory)
      out="$2"
      shift # past argument
      shift # past value
      ;;
    -v|--verbose)
      verbose="1"
      shift # past argument
      ;;
    -d|--details)
      showDetails="1"
      shift # past argument
      ;;
    -k|--insecure)
      secureOption="-k"
      shift # past argument
      ;;
    --local-time)
      localTime="1"
      shift # past argument
      ;;
    --page-size)
      pageSize="$2"
      shift # past argument
      shift # past value
      ;;
    --help)
      shift # past argument
      action="help"
      ;;
    -*|--*)
      echo "ERROR: Invalid parameter, '$1'"
      exit 22
      ;;
    *)
      echo "ERROR: Invalid parameter x, '$1'"
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

echo "---------------------------------------------------"
echo ""

if [[ "$active" == "1" ]]
then
    fetchActiveComputeSessions
fi
if [[ "$today" == "1" ]]
then
    fetchComputeSessionsFromToday
fi
if [[ "$week" == "1" ]]
then
    fetchComputeSessionsFromThisWeek
fi

if [[ "$all" == "1" && "$since" != "" ]]
then
    echo "The --all and --since options should not be used together."
    rc=22
    exit $rc
fi

if [[ "$all" == "1" ]]
then
    fetchAllComputeSessions
fi

if [[ "$since" != "" || "$before" != "" ]]
then
    fetchComputeSessionsCustomDate
fi
