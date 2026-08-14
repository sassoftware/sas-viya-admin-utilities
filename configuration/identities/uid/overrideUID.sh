#!/bin/bash 

#
# Overrides the UID/GID values for a given user or group.  By default this script will run psql commands on a machine within the Kubernetes
# cluster by exec'ing into the appropriate pod.  If exec/ssh privileges are not available this script can also be run externally (outside of 
# the cluster).  Doing so however will temporarily open up access to the database port in order to issue the queries.
#

function showHelp {
   echo ""
   echo "This script will override UID/GID values for a given user or group.  This script can either be run on a machine within the Kubernetes cluster or can be run externall, as long as the Postgres Client (psql) is available."
   echo ""
   echo "When Viya is configured with an external Postgres instance, make sure to set the following environment variables prior to executing this script:"
   echo "  - VIYA_DB_SECRET_NAME - the name of the secret associated with the 'dbmsowner' user"
   echo "  - VIYA_DB_CLUSTER_NAME - the name of the Postgres cluster, defaults to 'sas-crunchy-platform-postgres'"
   echo "  - VIYA_DB_CONTAINER_NAME - the main container name of the Postgres database, defaults to 'database'"
   echo ""
   echo "Examples:"
   echo ""
   echo " 1. Replace existing values for user: ./overrideUID.sh --namespace {kubernetes namespace} --user {userId} --uid {uid} --gid {gid}"
   echo " 2. Replace existing values for group: ./overrideUID.sh --namespace {kubernetes namespace} --group {groupId} --gid {gid}"
   echo " 3. Remove values for user: ./overrideUID.sh --namespace {kubernetes namespace} --remove --user {userId}"
   echo " 4. Remove values for all users and groups: ./overrideUID.sh --namespace {kubernetes namespace} --remove --all"
   echo ""
   echo "Parameters:"
   echo ""
   echo " -u|--user = The user id to update"
   echo " -g|--group = The group id to update"
   echo " --uid = The user's UID number"
   echo " --gid = The primary GID number"
   echo " -r|--remove = Removes existing uid/gid values"
   echo " -a|--all = Runs the command against all users and groups"
   echo " -n|--namespace = The kubernetes namespace to issue the commands against"
   echo " -e|--external = Runs the commands externally, without requiring exec/ssh access into the cluster."
   echo ""   
}

function checkKubernetesAccess {
    kubectl=`which kubectl 2>&1 | grep -v "no kubectl"`
    if [[ "$kubectl" == "" ]]
    then
        echo "ERROR: Could not find kubectl command location."
        exit 1
    fi
}

function checkPsqlAccess {
    psql=`which psql 2>&1 | grep -v "no psql"`
    if [[ "$psql" == "" ]]
    then
        echo "ERROR: Could not find psql command location."
        exit 1
    fi
}

function submitRequest {
    namespace=$1
    pod=$2
    sql=$3
    if [[ "$external" == "1" ]]
    then
        # fetch the secret to use for all udpate commands
        secret=`kubectl get secret $dbSecretName -o json | jq -r '.data.password | @base64d'`
        if [[ "$secret" == "" ]]
        then
            echo "ERROR: unable to find database secret password"
            exit 22
        fi
        # submit the request using psql directly
        response=$( PGPASSWORD=$(echo $secret) psql -t -d SharedServices -h localhost -U $dbUser -p $dbPort -c "$sql" )
    else
        # submit the request by exec'ing into the pod
        response=$( kubectl exec -i -n $namespace $pod -c $dbContainerName -- psql -t -d SharedServices -c "$sql" )
    fi
    echo "$response"
}

function initialize {
    namespace=$1
    pod=$2
    if [[ "$external" == "1" ]]
    then
        echo "Opening access to port $dbPort"
        kubectl -n $namespace port-forward $pod $dbPort:$dbPort &
        portForwardPID=`echo $!`
        sleep 8
    fi
}

function terminate {
    if [[ "$external" == "1" ]]
    then    
        echo "Closing access to port $dbPort"
        if [[ "$portForwardPID" != "" ]]
        then
            kill "$portForwardPID"
        fi
    fi
}

# Detects the Primary node in the Crunchy cluster
function getPrimary() {
    local x ns
    ns=$1
    x=$(  kubectl -n ${ns} get pods --no-headers --selector="postgres-operator.crunchydata.com/role=master" | cut -d' ' -f1 )
    if [[ $? != "0" ]]; then 
        return $?
    fi 
    echo ${x}
}

dirname=`dirname "$0"`
thispath=`cd "$dirname"; pwd`

#################################################################
#  Main
#################################################################

namespace=""
userId=""
groupId=""
uid=""
gid=""
remove="0"
all="0"
external="0"
action=""

dbUser="dbmsowner"
dbPort="5432"

#  Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace)
      namespace="$2"
      shift # past argument
      shift # past value
      ;;    
    -u|--user)
      userId="$2"
      shift # past argument
      shift # past value
      ;;
    -g|--group)
      groupId="$2"
      shift # past argument
      shift # past value
      ;;
    -a|--all)
      all="1"
      shift # past argument
      ;;
    -r|--remove)
      remove="1"
      shift # past argument
      ;;
    -e|--external)
      external="1"
      shift # past argument
      ;;
    --uid)
      uid="$2"
      shift # past argument
      shift # past value
      ;;
    --gid)
      gid="$2"
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

# verify kubectl is available
checkKubernetesAccess

# verify psql is available (if running externally)
if [[ "$external" == "1" ]]
then
    checkPsqlAccess
fi

# verify the k8s namespace has been set
if [[ "$namespace" == "" ]]
then
    echo "ERROR: kubernetes namespace must be passed as a parameter."
    exit 22
fi

if [[ "$userId" != "" && "$groupId" != "" ]]
then
    echo "ERROR: specify either a user id or a group id"
    exit 22
fi
 
# initialize database resource names
if [[ "$VIYA_DB_CLUSTER_NAME" != "" ]]
then
    dbClusterName="$VIYA_DB_CLUSTER_NAME"
else
    dbClusterName=$(getPrimary $namespace)
fi
if [[ "$VIYA_DB_CONTAINER_NAME" != "" ]]
then
    dbContainerName="$VIYA_DB_CONTAINER_NAME"
else
    dbContainerName="database"
fi
if [[ "$VIYA_DB_SECRET_NAME" != "" ]]
then
    dbSecretName="$VIYA_DB_SECRET_NAME"
else
    dbSecretName="sas-crunchy-platform-postgres-pguser-dbmsowner"
fi

echo "Searching for proper database container to connect to"
pod=$( kubectl -n $namespace get pod --no-headers | grep $dbClusterName | cut -d' ' -f1 | head -1 )
if [[ $pod == "" ]]
then
    echo "ERROR: unable to find database pod"
    exit 22
fi

echo "Establishing connection to database pod: $pod"
initialize $namespace $pod

sql=""
if [[ "$remove" == "1" ]]
then
    if [[ "$userId" != "" ]]
    then
        # remove the entries for the specified user
        echo "Removing uid/gid information for user $userId"
        sql="DELETE FROM identities.extended_attributes WHERE identity_id='$userId' AND identity_type_cd=0"
    elif [[ "$groupId" != "" ]]
    then
        # remove the entries for the specified group
        echo "Removing gid information for group $groupId"
        sql="DELETE FROM identities.extended_attributes WHERE identity_id='$groupId' AND identity_type_cd=1"
    elif [[ "$all" == "1" ]]
    then
        # remove all entries
        echo "Removing uid/gid information for all users and groups"
        sql="DELETE FROM identities.extended_attributes"
    else
        echo "WARNING: nothing to remove.  Specify either a user or group id, or the --all flag."
        exit 22
    fi
else
    if [[ "$userId" != "" ]]
    then
        # update the user's values
        if [[ "$uid" == "" || "$gid" == "" ]]
        then
            echo "Must specify a uid and gid value to update"
            exit 22
        fi
        echo "Fetching existing UID/GID information for user $userId"
        sql="SELECT COUNT(*) FROM identities.extended_attributes WHERE identity_id='$userId' AND identity_type_cd=0"
        response=$( submitRequest "$namespace" "$pod" "$sql" )
        count=$( echo -e "${response}" | tr -d '[:space:]' )
        if [[ "$count" == "0" ]]
        then
            echo "Inserting uid/gid information for user $userId"
            sql="INSERT INTO identities.extended_attributes (identity_id, identity_type_cd, identity_provider_id, identity_uid, identity_gid) VALUES ('$userId', 0, 'ldap', $uid, $gid)"
        else
            echo "Updating uid/gid information for user $userId"
            sql="UPDATE identities.extended_attributes SET identity_uid=$uid, identity_gid=$gid, identity_provider_id='ldap' WHERE identity_id='$userId' AND identity_type_cd=0"
        fi
    elif [[ "$groupId" != "" ]]
    then
        # update the group's values
        if [[ "$gid" == "" ]]
        then
            echo "Must specify a gid value to update"
            exit 22
        fi
        echo "Fetching existing UID/GID information for group $groupId"
        sql="SELECT COUNT(*) FROM identities.extended_attributes WHERE identity_id='$groupId' AND identity_type_cd=1"
        response=$( submitRequest "$namespace" "$pod" "$sql" )
        count=$( echo -e "${response}" | tr -d '[:space:]' )
        if [[ "$count" == "0" ]]
        then
            echo "Inserting gid information for group $groupId"
            sql="INSERT INTO identities.extended_attributes (identity_id, identity_type_cd, identity_provider_id, identity_gid) VALUES ('$groupId', 1, 'ldap', $gid)"
        else
            echo "Updating gid information for group $groupId"
            sql="UPDATE identities.extended_attributes SET identity_gid=$gid, identity_provider_id='ldap' WHERE identity_id='$groupId' AND identity_type_cd=1"
        fi
    fi
fi

# execute the request
response=$( submitRequest "$namespace" "$pod" "$sql" )
echo "Response: $response"

# close the database connection
terminate