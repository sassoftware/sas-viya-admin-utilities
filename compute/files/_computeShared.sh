#  A set of common functions intended to be sourced into other scripts

computeSharedPath=`cd "$(dirname "${BASH_SOURCE[0]}")"; pwd`
. "$computeSharedPath/../../common/_shared.sh"

function getComputeContextId {
    local name="$1"    
    local encodedName="${name// /%20}"
    local uri="compute/contexts?filter=eq(name,'$encodedName')"
    read computeContextId  < <(echo $(curl -s "$secureOption" "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | jq -r '.items[0].id'))
    echo $computeContextId
}

function startComputeSession {
    local computeContextId="$1"
    local uri="compute/contexts/$computeContextId/sessions"
    read sessionId  < <(echo $(curl -s -S "$secureOption" -X POST "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken" | jq -r '.id'))
    echo "$sessionId"
}

function terminateComputeSession {
    local sessionId="$1"
    local uri="compute/sessions/$sessionId"
    curl -s -S "$secureOption" -X DELETE "$urlRoot/$uri" -H "Accept: application/json" -H "Authorization: Bearer $accessToken"
}

function waitSession {
    local sessionId="$1"
    waitStart=$SECONDS
    headers="/tmp/headers-$timestamp.txt"
    etag=""
    wait=10
    while :
    do
        if [[ "$etag" == "" ]]
        then 
            status=`curl -s -S "$secureOption" $urlRoot/compute/sessions/$sessionId/state -H "Authorization: Bearer $accessToken" -H "Accept: application/json" -D $headers`
        else
            status=`curl -s -S "$secureOption" $urlRoot/compute/sessions/$sessionId/state?wait=$wait -H "Authorization: Bearer $accessToken" -H "Accept: application/json" -D $headers -H "If-None-Match: $etag"`
        fi
        httpStatusCode=`grep -E '^HTTP/' $headers | cut -d' ' -f2`
        case "$httpStatusCode"
            in
            "200")
                counter=$(($SECONDS - $start))
                if [[ "$etag" != "" ]]
                then
                    # If this isn't the first request and we get a 200, then it's ready
                    echo "Session $sessionId is ready."
                    rc=0
                    break
                else
                    # On the very first request, it is possible that the server is already ready, but will still return a 200 status code.  Thus, so we don't wait 
                    # forever, check the status also to see what to do.
                    if [[ "$status" == "idle" ]]
                    then
                        echo "Session $sessionId is ready."
                        rc=0
                        break
                    else
                        echo "Session $sessionId pending, elapsedTime=$counter seconds"
                    fi
                fi
                ;;
            "400")
                counter=$(($SECONDS - $start))
                echo "ERROR: A bad state request for session $sessionId was issued."
                rc=-2
                break
                ;;
            "404")
                counter=$(($SECONDS - $start))
                echo "ERROR: Passed session $sessionId not found."
                rc=-2
                break
                ;;
            "304")
                counter=$(($SECONDS - $start))
                echo "Session $sessionId pending, elapsedTime=$counter seconds"
                ;;
            *)
                echo "ERROR: Wait for Session state failed, status code=$httpStatusCode, message=$status"
                rc=$httpStatusCode
                break
                ;;
        esac

        if [[ "$etag" == "" ]]
        then
            etag=`grep -i 'ETag:' $headers | tr -d ' ' | tr -d '\r' | cut -d':' -f2` 
        fi
    done

    if [[ -f $headers ]]
    then
        rm -f $headers
    fi
}

function checkProfile {

    #  Make sure that the SAS CLI profile value is set and valid

    if [[ "$SAS_CLI_PROFILE" == "" ]]; then
        echo "ERROR: SAS command line profile variable, SAS_CLI_PROFILE, not set."
        exit 22
    fi

    cliProfile="$SAS_CLI_PROFILE"

    getViyaCLICommand
    profileExists=$("$sasCLICommand" profile list | grep $cliProfile)

    if [[ "$profileExists" == "" ]]; then
        echo "ERROR: specified profile $cliProfile does not exist"
        rc=22
        exit $rc
    else
        echo "Using profile $cliProfile"
    fi

}

function checkSSLCert {
    #   Validate the environment for running the sas-viya cli

    #  Validate the SSL Certificate is set up

    if [[ "$SSL_CERT_FILE" == "" ]]; then
        #    When using an internally generated cert file, the SSL_CERT_FILE must be specified
        #    However, when a customer cert file is used, SSL_CERT_FILE doesn't have to be specified and finding
        #    the right file name to specify is a pain.
        #    Thus, i'm going to change this from an error to a warning.
        #    If it it truly needs to be set for the commands to work, the test command in validateCLISetup should fail
        #    anyway.

        echo "WARNING: The ssl certificate file was not specified in the environment variable SSL_CERT_FILE"
    #   echo "ERROR: The ssl certificate file must be specified in the environment variable SSL_CERT_FILE"
    #   rc=22
    #   exit $rc
    fi

}

# Viya 3 or Viya 4?

function getViyaCLICommand {

    viya3=$(which sas-admin 2>&1 | grep -v "no sas-admin")

    if [[ "$viya3" != "" ]]; then
        sasCLICommand="$viya3"
        sasCLIVersion="3"
    else
        viya4=$(which sas-viya 2>&1 | grep -v "no sas-viya")

        if [[ "$viya4" != "" ]]; then
            sasCLICommand="$viya4"
            sasCLIVersion="4"
        else
            echo "ERROR: Could not find sas-admin nor sas-viya command location."
            exit 1
        fi

    fi

}

function validateCLISetup {

    checkProfile

    if [[ "$secureOption" == "" ]]; then
        checkSSLCert
    fi

    #  Validate that a command execution would work properly
    validateCLISetupTimestamp=$(date +%Y%m%d%H%M%S%N)
    validationFile="/tmp/sasviyaValidation_${validateCLISetupTimestamp}.txt"

    "$sasCLICommand" $secureOption identities whoami 2>&1 | tee "$validationFile"

    hasErrors=$(grep "errors" "$validationFile")

    if [[ -f "$validationFile" ]]; then
        rm "$validationFile"
    fi

    if [[ "$hasErrors" != "" ]]; then
        echo "ERROR: $sasCLICommand validation command failed"
        exit 22
    fi

}