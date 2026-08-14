#!/bin/bash

#######################################################
function showHelp {
   echo ""
   echo "This script will loop over the files in a directory and perform the appropriate context actions"
   echo "   *-compute.json = add a compute context"
#   echo "      *-compute-perms.csv = will additionally add these permissions to the compute context"
   echo "   *-launcher.json = add a launcher context"
   echo "   *-batch.csv = add a simple batch context"
   echo "   *-batch.json = add a batch context"
#   echo "     *-batch-perms.csv = will additionally add these permissions to the batch context"
   echo "   overlays/* = will create a pod template for each overlay directory"
   echo ""

   echo " Parameters:"
   echo ""
   echo "  --help = show this help content"
   echo "   -d|--base-directory <directory> = set the base directory that holds the details of what to create (default is current working directory)"
   echo "   -i|--init = initialize a new context directory (use with -b to set the directory)"
   echo "   -t|--podtemplates = create the pod templates specified in the overlays directory"
   echo "   -n|--namespace <namespace> = if the -t option is specified, this parameter specifies the kubernetes namespace to work with"
   echo "   -c|--contexts = create all the contexts specified by the json and csv files in the base directory"
   echo "   -cb|--batch-contexts = create the batch contexts specified by the csv files in the base directory"
   echo "   -cc|--compute-contexts = create the compute contexts specified by the json files in the base directory"
   echo "   -cl|--launcher-contexts = create the launcher contexts specified by the json files in the base directory"
   echo "      NOTE: If any of the -c,-cb,-cc,-cl options are specified, the SAS administration cli environment must be set up correctly, including:"
   echo "            - sas-viya command is available on the path (ie. can be executed without specifying a full path"
   echo "            - SAS_CLI_PROFILE environment variable must be set to the sas cli profile name to use"
   echo "            - SSL_CERT_FILE if your cli profile is accessing an https endpoint, this environment variable must contain the ssl certificate file to use"
   echo "            - A valid authentication token must be active for the specified cli profile.  To create a valid token, use sas-viya auth login"
   echo "   -a|--all = all actions (same as specifying -t and -c), this is the default action."
   echo "   -g|--group = additional group to give read only permission on any created contexts, may be specified more than once if multiple groups are needed"
   echo "   -f|--force = replace any existing contexts by performing a delete operation then re-adding them"
   echo "   -k|--insecure = Ignore using certificates when issuing commands"
   echo ""
   echo "For more details see the manageContexts.md readme file"

}

dirname=`dirname "$0"`
thispath=`cd "$dirname" ; pwd `

#   Included shared functions

. "$thispath/../../common/_shared.sh"

#   This script will loop over the files in a directory and perform the appropriate context actions
#   *-compute.json = add a compute context
#      *-compute-perms.csv = will additionally add these permissions to the compute context
#   *-launcher.json = add a launcher context
#   *-batch.csv = add a batch context
#      *-batch-perms.csv = will additionally add these permissions to the batch context
#   overlays/* = will create a pod template for each overlay directory
#
#   
#   will create a compute context/launcher context/pod for each
#

#######################################################
function addPodTemplates {

#   Note: We have to get the current batch and compute pod
#         definition from the current system and then apply
#         updates to them to get the new definitions.
#         Any time the base template is updated, this will
#         need to be re-run to merge the changes

echo "Getting existing podTemplate sas-batch-pod-template as a base"
kubectl get podTemplates sas-batch-pod-template -n $namespace --output yaml > "$stagingDir/batch/sas-batch-pod-template.yaml"
echo "Getting existing podTemplate sas-compute-job-config as a base"
  kubectl get podTemplates sas-compute-job-config -n $namespace --output yaml > "$stagingDir/compute/sas-compute-pod-template.yaml"
echo "Getting existing podTemplate sas-connect-pod-template as a base"
kubectl get podTemplates sas-connect-pod-template -n $namespace --output yaml > "$stagingDir/connect/sas-connect-pod-template.yaml"

FileSearch="$baseDir/overlays/*/"
shopt -s nullglob
for podTemplateDirectory in $FileSearch
do
    dirBasename=`basename "$podTemplateDirectory"`

    #  Skip any directories that start with _

    if [[ "${dirBasename:0:1}" != "_" ]]
    then
	    templateName=`grep -a1 'metadata/name' "$podTemplateDirectory/create-pod-template.yaml" | grep 'value:' | cut -d':' -f2 | xargs`

	    exists=`kubectl get podtemplates $templateName -n $namespace  2>&1 | grep -v NotFound`

	    if [[ "$exists" != "" ]]
	    then
	       echo "Deleting existing podTemplate $templateName"
	       kubectl delete podtemplates $templateName -n $namespace
	    fi
	       
	    echo "Adding podTemplate Directory $podTemplateDirectory"

	    kubectl apply -k $podTemplateDirectory
     else
            echo "Skipping directory $podTemplateDirectory since it starts with an underscore."
     fi

done

#  Remove the files from the staging area so they don't get accidentally used in the future

if [[ -f "$stagingDir/batch/sas-batch-pod-template.yaml" ]]
then
   rm "$stagingDir/batch/sas-batch-pod-template.yaml"
fi
if [[ -f "$stagingDir/compute/sas-compute-pod-template.yaml" ]]
then
   rm "$stagingDir/compute/sas-compute-pod-template.yaml"
fi
if [[ -f "$stagingDir/connect/sas-connect-pod-template.yaml" ]]
then
   rm "$stagingDir/connect/sas-connect-pod-template.yaml"
fi

}

#######################################################
function addLaunchers {
FileSearch="$baseDir/*-launcher.json"
shopt -s nullglob
for launcher in $FileSearch
do

    fileBasename=`basename "$launcher"`

    #  Skip any files that start with _

    if [[ "${fileBasename:0:1}" != "_" ]]
    then
        timestamp=`date +%Y%m%d%H%M%S%N` 
	    launcherName=`grep '"name":' $launcher | cut -d'"' -f4`

        showResultsFile="$stagingDir/showResults_${timestamp}.txt"
	    sas-viya $secureOption --profile $cliProfile compute launchers show --name "$launcherName"  2>&1 | grep -v "was not found" > "$showResultsFile"

        create=1
        delete=0
        if [[ -s "$showResultsFile" ]]
        then
            if [[ "$force" == "1" ]]
            then
                # perform a force removal and then re-add the contexts
                echo "Performing force update of launcher context '$launcherName'" 
                delete="1"
            else
                # the launcher context already exists.  first we need to fetch the context and update the existing file to include the proper context id
                echo "Updating existing launcher context '$launcherName'"
                output="$stagingDir/launcher-output.json"
                contextId=`grep "^Id" "$showResultsFile" | tr -s ' ' | cut -d' ' -f2`
                launcherUri="launcher/contexts/$contextId"
                launcherContextToUpdate="$stagingDir/update-$fileBasename"
                cp "$launcher" "$launcherContextToUpdate"
                cat <<< $(jq --arg CONTEXT_ID "$contextId" '.id += $CONTEXT_ID' $launcherContextToUpdate) > $launcherContextToUpdate

                # fetch the etag header
                headers="headers.txt"
                curl -s "$secureOption" "$urlRoot/$launcherUri" -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken" -D $headers > /dev/null
                etag=`grep -i 'ETag:' $headers | tr -d ' ' | tr -d '\r' | cut -d':' -f2`
                rm $headers

                # now submit the PUT/udpate request using the above etag
                response=$(curl --write-out '%{http_code}' "$secureOption" --silent --output $output "$urlRoot/$launcherUri" -X PUT -d "@$launcherContextToUpdate" -H 'If-Match: '"$etag"'' -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken")
                if [[ "$response" == "200" ]]
                then
                    # the context was updated successfully, no need to attempt to recreate it
                    create=0
                    echo "The launcher context '$launcherName' was updated successfully."
                elif [[ "$response" == "404" ]]
                then
                    echo "Error: The launcher context '$launcherName' could not be found."
                else
                    delete=1
                    echo "Error: An unknown error occurred while updating the launcher context '$launcherName'.  Will attempt to recreate.  Status Code: $response"
                fi

                rm "$output"
                rm "$launcherContextToUpdate"
            fi
	    fi

        if [[ "$delete" == 1 ]]
        then
            echo "Deleting existing launcher context '$launcherName'"
            sas-viya $secureOption -y --profile $cliProfile compute launchers delete --name "$launcherName"
        fi

        if [[ "$create" == "1" ]]
        then
		    echo "Adding launcher context '$launcher'"
		    sas-viya $secureOption --profile $cliProfile compute launchers create -r -d @$launcher
                    createRC=$?
                    if [[ "$createRC" == "0" ]]
                    then
                        echo "Launcher context '$launcher' created successfully"
                    else
                        echo "Launcher context '$launcher' creation failed, rc=$createRC"
                    fi
        fi
    else
            echo "Skipping file $launcher since it starts with an underscore."
    fi

done

}

#######################################################
function processBatchContext {

                    #  This routine contains the common processing between processing a simple batch context request and a normal batch context request
                    #
                    #  Inputs:
                    #    - batchContext = the name of the file being processed
                    #    - batchName = the name of the batch context being processed
                    #
                    #    - batchType = if batchType=simple, then 
                    #                  launcherName = must be set to the name of the launcher to use
                    #                  batchDescription = the description to use on this launcher
                    #                = if batchType=normal, then
                    #                  no other options are needed

                    timestamp=`date +%Y%m%d%H%M%S%N`

                    listResultsFile="$stagingDir/listResults_${timestamp}.txt"
                    sas-viya $secureOption --profile $cliProfile batch contexts list --name "$batchName"  2>&1 | grep -v "Launcher Context ID" > "$listResultsFile"
                    
                    create=1
                    delete=0
                    if [[ -s "$listResultsFile" ]]
                    then
                        if [[ "$force" == "1" ]]
                        then
                            # perform a force removal and then re-add the contexts
                            echo "Performing force update of batch context '$batchName'" 
                            delete="1"
                        else
                            echo "Updating existing batch context '$batchName'"
                            contextId=`grep "^ID" "$listResultsFile" | tr -s ' ' | cut -d' ' -f2`

                            if [[ "$batchType" == "simple" ]]
                            then
                                sas-viya $secureOption --profile $cliProfile batch contexts update --id "$contextId" --name "$batchName" --description "$batchDescription" --launcher-context-name "$launcherName"
                            else
                                sas-viya $secureOption --profile $cliProfile batch contexts update --id "$contextId" --json-file "$batchContext"
                            fi
                            create=0
                        fi
                    fi
                    if [[ -f "$listResultsFile" ]]
                    then
                       rm "$listResultsFile"
                    fi

                    if [[ "$delete" == 1 ]]
                    then
                        echo "Deleting existing batch context '$batchName'"
                        sas-viya $secureOption -y --profile $cliProfile batch contexts delete --name "$batchName"
                    fi

                    if [[ "$create" == 1 ]]
                    then
			    resultsFile="$stagingDir/contextResults_${timestamp}.txt"
			    if [[ "$batchType" == "simple" ]]
			    then
				    echo "Adding batch context '$batchName' with launcher '$launcherName'"

				    sas-viya $secureOption --profile $cliProfile batch contexts create --name "$batchName" --description "$batchDescription"  --launcher-context-name "$launcherName" | tee "$resultsFile"
                                    createRC=$?
			    else
				    echo "Adding batch context '$batchName' from file '$batchContext'"

				    sas-viya $secureOption --profile $cliProfile batch contexts create --json-file "$batchContext" | tee "$resultsFile"
                                    createRC=$?

			    fi

			    #  Parse out the Id of the new context

			    contextId=`grep "^ID" "$resultsFile" | tr -s ' ' | cut -d' ' -f2`

			    if [[ -f "$resultsFile" ]]
			    then
			       rm "$resultsFile"
			    fi

                            if [[ "$createRC" == "0" && "$contextId" != "" ]]
                            then
				    #  NOTE: Setting permissions is only supported for the normal batch file, not the simple batch file!
				    #
				    #  NOTE: the batch context input file doesn't actually have an authorizedGroups entry, however, taking
				    #        advantage of the fact that it doesn't check to have it in the input file so we can parse it out.
				    #  The syntax of the line is simple:
				    #      "authorizedGroups": "<group id>"

				    if [[ "$batchType" != "simple" ]]
				    then
					    uri="/batch/contexts/$contextId"

					    contextFile="$batchContext"
					       
					    contextGroupName=`grep "authorizedGroups" "$batchContext" | cut -d'"' -f4`

					    setContextPermissions

				    fi
                            else
                                    echo "ERROR: Creation of batch context $batchContext failed."
                            fi

                    fi

}

#######################################################
function addBatchContexts {

        #  Initially, adding a batch context through the cli did not provide many options
        #  However, as it improved, more capabilities were added that gave you more control over
        #  what was created.
        #  To provide backward compatibility, there are 2 formats accepted for creating batch contexts:
        #  *-batch.csv = used to create a simple batch context in which the csv file contains context name, context description
        #                and launcher name
        #  *-batch.json = used to create any batch context that is supported through the cli.  This is equivalent to the
        #                to the processing capabilities of compute and launcher contexts.
        #  Need to look for both of these types

        addSimpleBatchContexts

        addNormalBatchContexts
       
}

#######################################################
function addNormalBatchContexts {

FileSearch="$baseDir/*-batch.json"
shopt -s nullglob
for batchContext in $FileSearch
do

    fileBasename=`basename "$batchContext"`

    #  Skip any files that start with _

    if [[ "${fileBasename:0:1}" != "_" ]]
    then

            #  Get name of the context from the file contents name property

            batchName=`grep '"name":' $batchContext | cut -d'"' -f4`

            batchType="normal"
            processBatchContext

    fi

done


}

#######################################################
function addSimpleBatchContexts {

#   For each batch context to create, there is a file in the form
#   name,desc,launcher
#

FileSearch="$baseDir/*-batch.csv"
shopt -s nullglob
for batchContext in $FileSearch
do

    fileBasename=`basename "$batchContext"`

    #  Skip any files that start with _

    if [[ "${fileBasename:0:1}" != "_" ]]
    then

	    timestamp=`date +%Y%m%d%H%M%S%N`
	    while IFS=',' read -r batchName batchDescription launcherName; do

                    batchType="simple"
                    processBatchContext

	    done < "$batchContext"

    else
            echo "Skipping file $batchContext since it starts with an underscore."

    fi

done

}

#######################################################
function addComputeContexts {

shopt -s nullglob
FileSearch="$baseDir/*-compute.json"
for computeContext in $FileSearch
do

    fileBasename=`basename "$computeContext"`

    #  Skip any files that start with _

    if [[ "${fileBasename:0:1}" != "_" ]]
    then

	    timestamp=`date +%Y%m%d%H%M%S%N` 

	    contextName=`grep '"name":' $computeContext | cut -d'"' -f4`

	    showResultsFile="$stagingDir/showResults_${timestamp}.txt"
	    sas-viya $secureOption --profile $cliProfile compute contexts show --name "$contextName"  2>&1 | grep -v "was not found" > "$showResultsFile"

        create=1
        delete=0
        if [[ -s "$showResultsFile" ]]
        then
            if [[ "$force" == "1" ]]
            then
                # perform a force removal and then re-add the contexts
                echo "Performing force update of compute context '$contextName'" 
                delete="1"
            else
                # the compute context already exists.  the logic below will attempt to update its contents, but first we need to fetch the context and update the existing file to include the proper context id
                echo "Updating existing compute context '$contextName'"
                output="$stagingDir/compute-output.json"
                contextId=`grep "^Id" "$showResultsFile" | tr -s ' ' | cut -d' ' -f2`
                computeUri="compute/contexts/$contextId"
                computeContextToUpdate="$stagingDir/update-$fileBasename"
                cp "$computeContext" "$computeContextToUpdate"
                cat <<< $(jq --arg CONTEXT_ID "$contextId" '.id += $CONTEXT_ID' $computeContextToUpdate) > $computeContextToUpdate

                # fetch the etag header
                headers="headers.txt"
                curl -s "$secureOption" "$urlRoot/$computeUri" -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken" -D $headers > /dev/null
                etag=`grep -i 'ETag:' $headers | tr -d ' ' | tr -d '\r' | cut -d':' -f2`
                rm $headers

                # now submit the PUT/udpate request using the above etag
                response=$(curl --write-out '%{http_code}' "$secureOption" --silent --output $output "$urlRoot/$computeUri" -X PUT -d "@$computeContextToUpdate" -H 'If-Match: '"$etag"'' -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $accessToken")
                if [[ "$response" == "200" ]]
                then
                    # the context was updated successfully, no need to attempt to recreate it
                    create=0
                    echo "The compute context '$contextName' was updated successfully."
                elif [[ "$response" == "404" ]]
                then
                    echo "Error: The compute context '$contextName' could not be found."
                else
                    delete=1
                    echo "Error: An unknown error occurred while updating the compute context '$contextName'.  Will attempt to recreate.  Status Code: $response"
                fi

                rm "$output"
                rm "$computeContextToUpdate"
            fi
       fi

	    if [[ -f "$showResultsFile" ]]
	    then
	       rm "$showResultsFile"
	    fi

            if [[ "$delete" == "1" ]]
            then
                echo "Deleting existing compute context '$contextName'"
                sas-viya $secureOption -y --profile $cliProfile compute contexts delete --name "$contextName"
            fi

            if [[ "$create" == "1" ]]
            then

		    echo "Adding compute context '$computeContext'"

		    resultsFile="$stagingDir/contextResults_${timestamp}.txt"
		   
		    sas-viya $secureOption --profile $cliProfile compute contexts create -r -d @$computeContext | tee "$resultsFile"
                    createRC=$?
		   
		    #  Parse out the Id of the new context

		    contextId=`grep "^Id" "$resultsFile" | tr -s ' ' | cut -d' ' -f2`

         	    #  Parse out the Id of the new context
		    if [[ -f "$resultsFile" ]]
		    then
		       rm "$resultsFile"
		    fi

                    if [[ "$createRC" == "0" && "$contextId" != "" ]]
                    then

			    #  Parse out the Id of the new context

			    uri="/compute/contexts/$contextId"
			   
			    #  Get the group that has been granted permissions for sessions

			    contextGroupName=`grep -a1 "authorizedGroups" "$computeContext" | grep -v "authorizedGroups\|}" | cut -d'"' -f2`

			    setContextPermissions
                    else
                            echo "ERROR: Creation of compute context '$computeContext' failed."
                    fi

            fi

    else
            echo "Skipping file $computeContext since it starts with an underscore."

    fi
    
done

}

#######################################################
function setContextPermissions {

   #  This routine will set the permissions on the context so that only 
   #  groups that can launch sessions can see the context at all.
   #
   #  Be careful to set the group name properly or no one will be able to see it!

   if [[ "$contextGroupName" != "" ]]
   then
      echo "Removing others besides $contextGroupName to see the context $uri."

      additionalGroups=""
      if (( ${#readOnlyGroups[@]} != 0 ))
      then
          echo "Including additional groups for read only access"
          for i in ${!readOnlyGroups[@]}; do
              additionalGroups+=" and !groupsForCurrentUser().contains(\"${readOnlyGroups[$i]}\")"
          done
      fi

      sas-viya $secureOption authorization prohibit --everyone --object-uri "$uri" --condition '!groupsForCurrentUser().contains("SASAdministrators") and !groupsForCurrentUser().contains("sasapp") and !groupsForCurrentUser().contains("'$contextGroupName'")'"$additionalGroups"'' -p Read
   else
      echo "No context group name found, skipping setting permissions on context $context $uri"
   fi

}

#######################################################
function makeSubdirectory {

  if [[ ! -d "$makeDir" ]]
  then
     mkdir "$makeDir"
     rc=$?
     if [[ "$rc" != "0" ]]
     then 
        exit $rc
     fi
  fi

}

#######################################################
function initDirectory {
  echo "Initialize the directory $baseDir for use"

  rc=0

  makeDir="$baseDir"
  makeSubdirectory

  #  Create the initial content in the directory

  cp -r "$thispath"/samples/_initialContextDirectoryContent/* "$baseDir"
  rc=$?

  exit $rc
}

####################################
#   Main
####################################

dirname=`dirname "$0"`
thispath=`cd "$dirname" ; pwd `

namespace=""
scope=""

allPodTemplates="podtemplates"
allContexts="batchcontexts launchercontexts computecontexts"
action="make"

secureOption=""
readOnlyGroups=()

baseDir="$PWD"

###  Parse the arguments

while [[ $# -gt 0 ]]; do
  case $1 in
    # TODO: Add additional parameters
    #       -m|--make create contexts from the current directory (default)
    #       -w|--wipe|--delete delete all items that are described in the current directory
    #       -x|--wipe-contexts|--delete-contexts delete all contexts described in this current directory
    #       -y|--wipe-pod-templates|--delete-pod-templates delete all pod templates described in this current directory
    -d|--base-directory)
      # set the base directory (default is current working directory)
      baseDir="$2"
      shift # past argument
      shift # past value
      ;;
    -k|--insecure)
      secureOption="-k"
      shift # past argument
      ;;
    -i|--init)
      action="init"
      shift # past argument
      ;;
    -n|--namespace)
      namespace="$2"
      shift # past argument
      shift # past value
      ;;
    -a|--all)
      #  Add all scopes to the scope variable
      scope="$scope podtemplates contexts"
      shift # past argument
      ;;
    -g|--group)
      readOnlyGroups+=( "$2" )
      shift # past argument
      shift # past value
      ;;
    -c|--contexts)
      scope="$scope $allContexts"
      shift # past argument
      ;;
    -cl|--launcher-contexts)
      scope="$scope launchercontexts"
      shift # past argument
      ;;
    -cc|--compute-contexts)
      scope="$scope computecontexts"
      shift # past argument
      ;;
    -cb|--batch-contexts)
      scope="$scope batchcontexts"
      shift # past argument
      ;;
    -t|--podtemplates)
      scope="$scope $allPodTemplates"
      shift # past argument
      ;;
    -f|--force)
      force="1"
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

#  Done parsing args, continue

stagingDir="$baseDir/staging"

#  Handle some high level actions first

if [[ "$action" == "help" ]]
then
   showHelp
   exit 0
fi

if [[ "$action" == "init" ]]
then
    echo "calling initDirectory"
    initDirectory
fi

#  Make sure the requested directory exists
if [[ ! -d "$baseDir" ]]
then
   echo "ERROR: Base directory, $baseDir, does not exist"
   exit 22
else
   #  Make sure it looks like a context directory

   if [[ ! -d "$stagingDir" || ! -d "$baseDir/overlays" ]]
   then
      echo "ERROR: $baseDir does not look like the directory structure needed for running this script"
      exit 22
   fi

fi

###  Validate arg values and set any defaults

if [[ "$scope" == "" ]]
then 
   scope="$allPodTemplates $allContexts"
fi
echo "scope=$scope"
#  namespace only required if creating pod templates

if [[ "$namespace" == "" && "$scope" == *"podtemplates"* ]]
then
   echo "ERROR: Kubernetes namespace parameter is required when creating pod templates"
   exit 22
fi

#  If we are going to do anything withe sas-viya cli, validate it first since it requires setup

if [[ "$scope" == *"contexts"* ]]
then
echo "validating CLI Setup"
	validateCLISetup
fi

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


#  Add the podTemplates, Launcher Contexts and Batch, Compute contexts

if [[ "$scope" == *"podtemplates"* ]]
then
   addPodTemplates
fi

if [[ "$scope" == *"contexts"* ]]
then

        if [[ "$scope" == *"launchercontexts"* ]]
        then
          addLaunchers
        fi

        if [[ "$scope" == *"batchcontexts"* ]]
        then
          addBatchContexts
        fi

        if [[ "$scope" == *"computecontexts"* ]]
        then
          addComputeContexts
        fi

fi

