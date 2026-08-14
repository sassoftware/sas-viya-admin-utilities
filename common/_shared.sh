#  A set of common functions intended to be sourced into other scripts

function getAccessToken {
    accessToken=`"$sasCLICommand" profile show --details --key "access-token"`
    echo "$accessToken"
}

function getUrlRoot {
    urlRoot=`"$sasCLICommand" profile show --details --key "sas-endpoint"`
    echo "$urlRoot"
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
