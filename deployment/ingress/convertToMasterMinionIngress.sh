#!/bin/bash

while [[ $# -gt 0 ]] ; do
case "$1" in 
  --input | -i)
    SITEYAML=$2
    shift
    shift
    ;;
  --output | -o)
    OUTLOCATION=$2
    shift
    shift
    ;;
  --namespace | -n)
    NAMESPACE="$2"
    shift
    shift
    ;;
  *)
    echo "ERROR:"
    exit 1
esac

if [[ "$SITEYAML" == "" ]] || [[ ! -f "$SITEYAML" ]]
then
  echo "ERROR: The input file, ${SITEYAML}, does not exist."
  exit 1
fi

if [[ "$OUTLOCATION" == "" ]]
then 
  OUTLOCATION="."
fi 

if [[ ! -d "$OUTLOCATION" ]]
then
  echo "ERROR: The output location, ${OUTLOCATION}, does not exist."
  exit 1
fi

if [[ "$NAMESPACE" == "" ]]
then
  NAMESPACE=$(yq '.metadata.namespace | select(.)' "$SITEYAML" | grep -v "\-\-\-" | sort | uniq)
  NSCOUNT=$(echo "$NAMESPACE" | wc -l)
  if [[ "$NSCOUNT" -ne 1 ]]
  then
    echo "ERROR: Requires 1 namespace. Found ${NSCOUNT}:" 
    echo "${NAMESPACE}"
    exit 1
  fi
fi

NEWYAML="/tmp/site.yaml.tmp"
MASTERYAML="/tmp/ingress_master.yaml.tmp"
FINALYAML="$OUTLOCATION/new_site.yaml"
cp "$SITEYAML" "$NEWYAML"

# Initialization
#########################################################################
# ***If the ingresses are defined differently this will be an issue.*** #
# ***Hopefully they each have the same deployment and TLS block     *** #
#########################################################################
FIRSTDOC=$(yq '. | select(.kind == "Ingress") | di' "$NEWYAML" | head -n 1)
DEPLOYMENTNAME=$(yq "select(di==$FIRSTDOC).metadata.labels.\"sas.com/deployment\"" "$NEWYAML")
TLSJSON=$(yq "select(di==$FIRSTDOC) | .spec.tls" -o=json "$NEWYAML")
# Collect the unique hosts defined in the ingresses
HOSTS=$(yq '. | select(.kind == "Ingress")' "$NEWYAML" | grep "host:" | sort -r | uniq | cut -d ':' -f2 | tr -d "' ")

ID=0

# Add the "minion" annotation to all existing ingress objects"
yq -i 'select(.kind == "Ingress").metadata.annotations."nginx.org/mergeable-ingress-type" |= "minion"' "$NEWYAML"
# The CAS CRD defines the ingress for the server, so it has to be manipulated differently
yq -i 'select(.kind=="CASDeployment").spec.ingressTemplate.metadata.annotations."nginx.org/mergeable-ingress-type" |= "minion"' "$NEWYAML"

# Add the nginx path-regex annotation to all existing ingres objects
yq -i 'select(.kind == "Ingress").metadata.annotations."nginx.org/path-regex" |= "case_insensitive"' "$NEWYAML"
# The CAS CRD defines the ingress for the server, so it has to be manipulated differently
yq -i 'select(.kind=="CASDeployment").spec.ingressTemplate.metadata.annotations."nginx.org/path-regex" |= "case_insensitive"' "$NEWYAML"

# Take out the TLS definition in all the minions
yq -i 'del(. | select(.kind=="Ingress").spec.tls)' "$NEWYAML"
# The CAS CRD defines the ingress for the server, so it has to be manipulated differently
yq -i 'del(. | select(.kind=="CASDeployment").spec.ingressTemplate.spec.tls)' "$NEWYAML"



# Masters (and minions) can only define a rules for a single host. 
# There are two hosts in some (all?) deployments <dnsname> and *.<dnsname>
# These have to be split into separate masters and minions
for HOST in ${HOSTS}
do
  # Create general Ingress template
  echo "---
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata: 
    name: sas-viya-ingress-master-host${ID}
    namespace: $NAMESPACE
    annotations:
      nginx.org/mergeable-ingress-type: \"master\"      
    labels:
      sas.com/admin: \"namespace\"   
      sas.com/deployment: \"${DEPLOYMENTNAME}\"    
  spec:
    ingressClassName: nginx
    rules:
      - host: \"${HOST}\"
    tls: []" > "${MASTERYAML}.${ID}"  
  
  yq -i ".spec.tls += ${TLSJSON}" "${MASTERYAML}.${ID}"
  ((ID++))
done

COUNT=$(echo "${HOSTS}" | wc -l)
# Decrement to use 0 indexed values
((COUNT--))

# Create a copy of the existing ingress resources - one for each host
# The original resources in site.yaml will be used for host0
for IDX in $(seq 1 $COUNT)
do
  yq 'select(.kind=="Ingress")' "$NEWYAML" > "$OUTLOCATION/host${IDX}.ingress.yaml" 
done

cat "$NEWYAML" > "$FINALYAML"
echo "---" >> "$FINALYAML"

for IDX in $(seq 0 $COUNT)
do
  if [[ "$IDX" == "0" ]]
  then
     target="$NEWYAML"
  else
     target="$OUTLOCATION/host${IDX}.ingress.yaml"
  fi
  
  yq -i "select(.kind==\"Ingress\").metadata.name += \"-host${IDX}\"" "$target"  
  for IDX2 in $(seq 0 $COUNT)
  do
    if [[ "$IDX2" != "$IDX" ]] 
    then
      yq -i "del(. | select(.kind==\"Ingress\").spec.rules[$IDX2])" "$target"
    fi
  done
  if [[ "$IDX" == "0" ]]
  then
    cat "$target" > "$FINALYAML"
    echo "---" >> "$FINALYAML"     
  else
    cat "$target" >> "$FINALYAML"
  fi
done

# Append the master ingress resources into the resulting output
for IDX in $(seq 0 $COUNT)
do
  cat "${MASTERYAML}.${IDX}"  >> "$FINALYAML"
done