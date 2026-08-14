
function printSeparator {
    echo ""
    echo "-------------------------"
    echo ""
}

function formatDate {
    inDate="$1"

    # convert the incoming date to seconds (all dates are in GMT by default)
    sec=$(TZ="GMT" date +'%s' -d "$inDate")

    # convert to local timezone
    currentTZ="$TZ"
    echo `TZ="$currentTZ" date -d "@$sec" +"%Y-%m-%dT%H:%M:%S.%3N %Z"`
}

function calculateSessionLength {
    local startTime=$1
    local endTime=$2

    let diff=(`date +%s -d $endTime`-`date +%s -d $startTime`)/60
    echo "$diff"
}

function submitActivitiesRequest {
    local filter="$1"
    local outputFile="$2"
    local pageNumber="$3"    
    let index=pageNumber-1
    
    start=$((pageSize * index))
    auditUri="audit/activities?limit=$pageSize&start=$start&sortBy=timeStamp:ascending&filter=$filter"
    curl -s $secureOption "$urlRoot/$auditUri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | tee $outputFile > /dev/null
}

