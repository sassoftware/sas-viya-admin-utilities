#!/bin/bash

#   This script will be passed the location of a file containing group information
#   and a context template directory.
#   It will then generate the appropriate information for each group that can then be
#   used by compute/manageContexts.sh script to define the contexts to the system.
#

#############################################################################
function showHelp {
    echo ""
    echo "This script will generate a directory of files and folders that is later used as input to manageContexts.sh"
    echo ""
    echo "Parameters:"
    echo ""
    echo "-f = A csv containing the list of groups to generate files for.  This file is in the format output by the capture/getSysInfo.sh groups command"
    echo "-t = a directory containing templates to use as input to the generation.  See samples for examples."
    echo "-o = the output directory with the generated files and directories.  This directory can then be used on the --base-directory option on manageContexts.sh"
    echo "-n = the kubernetes namespace to generate contexts for"
    echo ""

}

dirname=`dirname "$0"`
thispath=`cd "$dirname" ; pwd `
thisScript=`basename "$0"`

#############################################################################
function standardizeString {

    #  It looks like the most restrictive set of name rules is RFC 1035, which says
    #  - contain at most 63 characters
    #  - contain only lowercase alphanumeric characters or -
    #  - start with an alphabetic character
    #  - end with an alphanumeric character

#  only take the first 63 characters

outString="${inString:0:62}"

#  Lowercase the value

outString="${outString,,}"

# Change as many special characters that we can think of to -

outString=`echo "$outString" | tr ' :/><{}~!@#$%^&*()_+=;"?' '-' | tr "'" "-"`

# Change the first character to an alphabetic character
#  To try to avoid collisions, if it's a number, select that number'th character from the string
#  If it's a -, use the index 10
#
alphabet="abcdefghiji"

firstChar=${outString:0:1}
restChars=${outString:1}

if [[ ! "$firstChar" =~ ^[[:alpha:]]+$ ]]
then

   echo "not alphabetic"
   if [[ "$firstChar" =~ ^[[:digit:]]+$ ]]
   then
    echo "numeric"
    replacementChar=${alphabet:$firstChar:1}

   else
    echo "not numeric"
    replacementChar=${alphabet:10:1}
   fi

   outString="${replacementChar}${restChars}"
   # outString="${replacementChar}${outString}"
fi

# Change the last character to an alphanumeric character

lastChar=${outString: -1}
restChars=${outString:0: -1}

if [[ ! "$lastChar" =~ ^[[:alnum:]]+$ ]]
then
   replacementChar=${alphabet:10:1}
   outString="${restChars}${replacementChar}"
fi

}

#############################################################################
#  Depending on the value of the variable value, it might have special characters in it that conflict with the sed
#  syntax.  Try to find an acceptable value to use as the separator.
function getSedSeparator {

        sedDelimiters=("/" "|" ":")
        sedDelimiter=""
        for delimiter in ${sedDelimiters[@]}; do

          if [[ "$variableValue" != *"$delimiter"* ]]
          then
             sedDelimiter="$delimiter"
             break
          fi
        done

        if [[ "$sedDelimiter" == "" ]]
        then
           echo "ERROR: Could not find sed delimiter to use based on input value, $variableValue"
        fi

}

#############################################################################
function substituteVars {

    #  This routine will substitute values into the file passed (as substituteFile)
    #
    #  Variable references in the file need to be of the form ${variable}
    #
    #  There are some fixed variables that will be looked for:  groupid, groupName
    #
    #  The user can specify which other ones to look for in the properties file
    #

    #  If the user specified to use a properties file, then loop over every line
    #  there (that is not a comment) and do the substitution requested.

    if [[ -f "$propertiesFile" ]]
    then

       while IFS='\n' read -r propertiesLine; do

       if [[ "$propertiesLine" != "#"* && "$propertiesLine" != "" ]]
       then

          variableName=`echo "$propertiesLine" | cut -d'=' -f1`

          if [[ "$variableName" != "" ]]
          then
		  variableValue=`echo "$propertiesLine" | cut -d'=' -f2 | tr -d '"'`

		  getSedSeparator

		  if [[ "$sedDelimiter" != "" ]]
		  then
		    echo "substitute $variableValue for $variableName in file $substituteFile using sed Delimiter $sedDelimiter"
		    sed -i "s${sedDelimiter}\${${variableName}}${sedDelimiter}${variableValue}${sedDelimiter}g" "$substituteFile"
		  fi
          fi

       fi

       done < "$propertiesFile"

    fi

    #  Do these substitutions last in case the user used them in their substition values

    sed -i "s/\${groupid}/${groupid}/g" "$substituteFile"
    sed -i "s/\${groupName}/${groupName}/g" "$substituteFile"
    sed -i "s/\${namespace}/${namespace}/g" "$substituteFile"
    sed -i "s/\${serverType}/${serverType}/g" "$substituteFile"

    #  Note that any kubernetes resource, like pod templates, have pretty severe restrictions on 
    #  the names that can be used.  Thus, I will try to create a version of groupid and groupName that
    #  meet those.
    #  It looks like the most restrictive set of name rules is RFC 1035, which says
    #  - contain at most 63 characters
    #  - contain only lowercase alphanumeric characters or -
    #  - start with an alphabetic character
    #  - end with an alphanumeric character

    inString="$groupid"
    standardizeString
    sed -i "s/\${groupidStandardized}/${outString}/g" "$substituteFile"

    inString="$groupName"
    standardizeString
    sed -i "s/\${groupNameStandardized}/${outString}/g" "$substituteFile"
    
}
function overlaysSubstitute {

      if [[ "$overlayDir" != "" ]]
      then

         #  We found a directory to process.
         #  Loop over the files in the directory and do any text substitution on them

        FILES="$overlayDir/*"
        for f in $FILES
        do
          echo "Processing $f file..."
          substituteFile="$f"
          substituteVars
        done
      fi
}

#############################################################################
function processPodTemplateOverlays {

      #  Figure out what overlay-templates directory to use for this group
      #  If there is a directory that matches this group id, then use it
      #  If there is a directory that matches this group name, then use it
      #  Since there can be different types of pod templates, all for the same
      #  group (ex. batch, compute, connect, etc.), support a suffix of the 
      #  type on all choices.
      #  Otherwise, use the one marked template

      inOverlaysDir="$templateDirectory/overlay-templates"
      outOverlaysDir="$outDirectory/overlays"

      if [[ -d "$inOverlaysDir" ]]
      then
              #  For backward compatibility if we see a directory that matches the
              #  group, but doesn't have a suffix, assume it's compute.

              serverType="compute"

	      if [[ -d "$inOverlaysDir/${groupid}" ]]
	      then
		 cp -r -L "$inOverlaysDir/${groupid}" "$outOverlaysDir"
                 
		 overlayDir="$outOverlaysDir/${groupid}"
              elif [[ -d "$inOverlaysDir/${groupid}-compute" ]]
              then
                 cp -r -L "$inOverlaysDir/${groupid}-compute" "$outOverlaysDir"

                 overlayDir="$outOverlaysDir/${groupid}-compute"
	      elif [[ -d "$inOverlaysDir/${groupName}" ]]
	      then
		 cp -r -L "$inOverlaysDir/${groupName}" "$outOverlaysDir"
		 overlayDir="$outOverlaysDir/${groupName}"
              elif [[ -d "$inOverlaysDir/${groupName}-compute" ]]
              then
                 cp -r -L "$inOverlaysDir/${groupName}-compute" "$outOverlaysDir"
                 overlayDir="$outOverlaysDir/${groupName}-compute"
              elif [[ -d "$inOverlaysDir/template-compute" ]]
              then
                 cp -r -L "$inOverlaysDir/template-compute" "$outOverlaysDir/${groupid}-compute"
                 overlayDir="$outOverlaysDir/${groupid}-compute"
	      elif [[ -d "$inOverlaysDir/template" ]]
	      then
		 cp -r -L "$inOverlaysDir/template" "$outOverlaysDir/${groupid}"
		 overlayDir="$outOverlaysDir/${groupid}"
	      else
		 echo "WARNING: Not generating pod template due to not finding overlay definition for group id $groupid, group name=$groupName"
		 overlayDir=""
	      fi

              overlaysSubstitute

              #  Now look for batch

              overlayDir=""
              serverType="batch"

              if [[ -d "$inOverlaysDir/${groupid}-batch" ]]
              then
                 cp -r -L "$inOverlaysDir/${groupid}-batch" "$outOverlaysDir"

                 overlayDir="$outOverlaysDir/${groupid}-batch"
              elif [[ -d "$inOverlaysDir/${groupName}-batch" ]]
              then
                 cp -r -L "$inOverlaysDir/${groupName}-batch" "$outOverlaysDir"
                 overlayDir="$outOverlaysDir/${groupName}-batch"
              elif [[ -d "$inOverlaysDir/template-batch" ]]
              then
                 cp -r -L "$inOverlaysDir/template-batch" "$outOverlaysDir/${groupid}-batch"
                 overlayDir="$outOverlaysDir/${groupid}-batch"
              else
                 echo "WARNING: Not generating pod template due to not finding batch overlay definition for group id $groupid, group name=$groupName"
                 overlayDir=""
              fi

              overlaysSubstitute

              #  Now look for connect

              overlayDir=""
              serverType="connect"
              if [[ -d "$inOverlaysDir/${groupid}-connect" ]]
              then
                 cp -r -L "$inOverlaysDir/${groupid}-connect" "$outOverlaysDir"

                 overlayDir="$outOverlaysDir/${groupid}-connect"
              elif [[ -d "$inOverlaysDir/${groupName}-connect" ]]
              then
                 cp -r -L "$inOverlaysDir/${groupName}-connect" "$outOverlaysDir"
                 overlayDir="$outOverlaysDir/${groupName}-connect"
              elif [[ -d "$inOverlaysDir/template-connect" ]]
              then
                 cp -r -L "$inOverlaysDir/template-connect" "$outOverlaysDir/${groupid}-connect"
                 overlayDir="$outOverlaysDir/${groupid}-connect"
              else
                 echo "WARNING: Not generating pod template due to not finding connect overlay definition for group id $groupid, group name=$groupName"
                 overlayDir=""
              fi

              overlaysSubstitute

      else
	   echo "NOTE: No overlay-templates directory found, skipping pod template generation"
	   overlayDir=""
      fi

}
#############################################################################
function processLaunchers {

   launcherFile=""
   
   #  Processing launcher templates is complicated by the fact that it is not
   #  recommended that a compute context and a batch context share a launcher.
   #  This fact makes it difficult to know which template to use.
   #  TODO:  Need to make these search rules better!
   #  for example:
   #  If we find:
   #    - a <groupid>-batch-launcher, include it
   #    - a <groupid>-compute-launcher, include it
   #    - a <groupid>-launcher, include it
   #  otherwise:
   #    - a <groupid>-batch.*, include a template-batch-launcher.json
   #    - any template-batch.*, include a template-batch-launcher.json
   #    - a <groupid>-compute.*, include a template-compute-launcher.json
   #    - a template-compute.*, include a template-compute-launcher.json
   #    
   #

   #  Look for the batch launcher

   if [[ -f "$templateDirectory/${groupid}-batch-launcher.json" ]]
   then
      launcherFile="$templateDirectory/${groupid}-batch-launcher.json"
   elif [[ -f "$templateDirectory/template-batch-launcher.json" ]]
   then
      launcherFile="$templateDirectory/template-batch-launcher.json"
   fi

   if [[ "$launcherFile" != "" ]]
   then
         echo "Use launcher template $launcherFile for group $groupid"

         cp "$launcherFile" "$outDirectory/${groupid}-batch-launcher.json"

         substituteFile="$outDirectory/${groupid}-batch-launcher.json"

         serverType="batch"
         substituteVars
   fi

   #  Look for the compute launcher
   launcherFile=""

   if [[ -f "$templateDirectory/${groupid}-compute-launcher.json" ]]
   then
      launcherFile="$templateDirectory/${groupid}-compute-launcher.json"
   elif [[ -f "$templateDirectory/template-compute-launcher.json" ]]
   then
      launcherFile="$templateDirectory/template-compute-launcher.json"
   fi

   if [[ "$launcherFile" != "" ]]
   then
         echo "Use launcher template $launcherFile for group $groupid"

         cp "$launcherFile" "$outDirectory/${groupid}-compute-launcher.json"

         substituteFile="$outDirectory/${groupid}-compute-launcher.json"
         serverType="compute"
         substituteVars
   fi

}
#############################################################################
function processComputeContexts {
   contextFile=""

   if [[ -f "$templateDirectory/${groupid}-compute.json" ]]
   then
      contextFile="$templateDirectory/${groupid}-compute.json"
   elif [[ -f "$templateDirectory/template-compute.json" ]]
   then
      contextFile="$templateDirectory/template-compute.json"
   fi

   if [[ "$contextFile" != "" ]]
   then
         echo "Use compute context template $contextFile for group $groupid"

         cp "$contextFile" "$outDirectory/${groupid}-compute.json"

         substituteFile="$outDirectory/${groupid}-compute.json"
         serverType="compute"
         substituteVars
   fi

   
}

#############################################################################
function processBatchContexts {
       #  For backward compatibility, we support both a simple format (ie. csv) and a normal format (ie. .json)

       processSimpleBatchContexts
       processNormalBatchContexts

}

#############################################################################
function processSimpleBatchContexts {
   contextFile=""

   if [[ -f "$templateDirectory/${groupid}-batch.csv" ]]
   then
      contextFile="$templateDirectory/${groupid}-batch.csv"
   elif [[ -f "$templateDirectory/template-batch.csv" ]]
   then
      contextFile="$templateDirectory/template-batch.csv"
   fi

   if [[ "$contextFile" != "" ]]
   then
         echo "Use batch context template $contextFile for group $groupid"

         cp "$contextFile" "$outDirectory/${groupid}-batch.csv"

         substituteFile="$outDirectory/${groupid}-batch.csv"
         serverType="batch"
         substituteVars
   fi


}

#############################################################################
function processNormalBatchContexts {
   contextFile=""
echo "looking for normal batch context template"
   if [[ -f "$templateDirectory/${groupid}-batch.json" ]]
   then
      contextFile="$templateDirectory/${groupid}-batch.json"
   elif [[ -f "$templateDirectory/template-batch.json" ]]
   then
      contextFile="$templateDirectory/template-batch.json"
   fi

echo "search results: $contextFile"

   if [[ "$contextFile" != "" ]]
   then
         echo "Use batch context template $contextFile for group $groupid"

         cp "$contextFile" "$outDirectory/${groupid}-batch.json"

         substituteFile="$outDirectory/${groupid}-batch.json"
         serverType="batch"
         substituteVars
   fi


}

#############################################################################
#  Main
#############################################################################

action="process"
namespace=""

###  Parse the arguments

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--group-file)
      groupFile="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output-directory)
      outDirectory="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--namespace)
      namespace="$2"
      shift # past argument
      shift # past value
      ;;
    -t|--template-directory)
      templateDirectory="$2"
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

if [[ "$groupFile" == "" ]]
then
  echo "ERROR: group file must be passed as a parameter."
  showHelp

  exit 22
fi
if [[ ! -f "$groupFile" ]]
then
  echo "ERROR: group file, $groupFile, does not exist."

  exit 22
fi

if [[ "$templateDirectory" == "" ]]
then
  echo "ERROR: The name of the template directory must be passed as a parameter"
  showHelp
  exit 22
fi

if [[ "$namespace" == "" ]]
then
  echo "ERROR: The kubernetes namespace must be passed as a parameter"
  showHelp
  exit 22
fi

if [[ ! -d "$templateDirectory" ]]
then
   echo "ERROR: The passed template directory, $templateDirectory, does not exist."
   exit 22
fi

if [[ "$outDirectory" == "" ]]
then
  echo "ERROR: The name of the output directory must be passed as a parameter"
  showHelp
  exit 22
fi

if [[ -d "$outDirectory" ]]
then
   echo "NOTE: The passed output directory, $outDirectory, already exists"

   #  Verify that we have write access to the directory

   touch "$outDirectory/testwrite.txt"
   rc=$?

   if [[ "$rc" != "0" ]]
   then
      echo "ERROR: Can't write to output directory"
      exit 22
   fi

   rm "$outDirectory/testwrite.txt"

else
   echo "NOTE: Creating passed output directory, $outDirectory."
   
   mkdir -p "$outDirectory"
   rc=$?

   if [[ "$rc" != "0" ]]
   then
      echo "ERROR: Creating output directory failed"
      exit 22
   fi
fi

timestamp=`date +%Y%m%d%H%M%S%N`
rc=0

  #  The user can specify a properties file with the names and values that should be substituted into the template files

  propertiesFile="$templateDirectory/substitution.properties"

  if [[ -f "$propertiesFile" ]]
  then
     echo "NOTE: Will use properties from file $propertiesFile for substitution"
  else
     echo "NOTE: No properties file found, only default list of values will be replaced in templates"
  fi

  #  Initialize the output directory

  #  If we find files/directories in the directory that we are going to overlay, first back the file up to the
  #  backup directory 

  if [[ ! -d "$outDirectory/backup" ]]
  then
     mkdir "$outDirectory/backup"
  fi

  #  Create a backup directory specific to this run

  backupDir="$outDirectory/backup/bak.$timestamp"
  mkdir "$backupDir"

  if [[ -d "$outDirectory/staging" ]]
  then
     mv "$outDirectory/staging" "$backupDir"
  fi

  if [[ -d "$outDirectory/overlays" ]]
  then
     mv "$outDirectory/overlays" "$backupDir"
  fi

  #  Move any other files that may exist in the outDirectory to the backup directory
  mv $outDirectory/*.csv "$backupDir" 2>/dev/null
  mv $outDirectory/*.json "$backupDir" 2>/dev/null

  #  Initialize the generated context directory

  "$thispath/manageContexts.sh" -d "$outDirectory" -i

  # Figure out what type of content exists in the template directory so we don't have to check on each group
  # whether we should process that type of information or not.
  #

  inOverlaysDir="$templateDirectory/overlay-templates"
  if [[ -d "$inOverlaysDir" ]]
  then
     hasOverlays=1
  else
     hasOverlays=0
  fi

  hasLaunchers=`ls -1 $templateDirectory/*-launcher.json 2>/dev/null | wc -l`
  hasCompute=`ls -1 $templateDirectory/*-compute.json 2>/dev/null | wc -l`

  #  Look for both types of batch files

  hasBatch=`ls -1 $templateDirectory/*-batch.csv 2>/dev/null | wc -l`

  if [[ "$hasBatch" == "0" ]]
  then
    hasBatch=`ls -1 $templateDirectory/*-batch.json 2>/dev/null | wc -l`
  fi

  let hasProcessing=hasOverlays+hasLaunchers+hasCompute+hasBatch

  #  The input lines are in csv format, with each field surrounded by quotes
  #  The fields might contain , thus we can't do a delimited read on comma as the delimiter
  #  Instead, we will use the quote, which will allow for the embedded commas and will strip the quotes from each of the fields

  #  If no information was found in the directory to process, then don't waste the effort.

  if [[ "$hasProcessing" -gt 0 ]]
  then

  while IFS='"' read -r delim1 groupid delim2 groupName delim3 providerId delim4 groupState delim5 groupDescription delim6; do

          if [[ "$groupState" == "state" && "$groupDescription" == "description" ]]
          then
              echo "Skipping header line"
          else

		  if [[ "$groupState" == "active" ]]
		  then

		      echo "Processing group id $groupid, group name=$groupName"

                      #  There are 4 main types of information that can be created here:
                      #   1. New pod templates specific to this group.  The templates for these are in
                      #      overlay-templates in the input directory
                      #   2. Launcher definition.  The template for this is file that has a filename 
                      #      format of <name>-launcher.json.
                      #   3. Compute Context definition.  The template for this is file that has a filename 
                      #      format of <name>-compute.json.
                      #   4. Batch Context definition.  The template for this is file that has a filename 
                      #      format of <name>-batch.csv.
                      #
                      if [[ "$hasOverlays" == "1" ]]
                      then
                         processPodTemplateOverlays
                      fi

                      if [[ "$hasLaunchers" -gt 0 ]]
                      then
                         processLaunchers
                      fi

                      if [[ "$hasCompute" -gt 0 ]]
                      then
                        processComputeContexts
                      fi
                      if [[ "$hasBatch" -gt 0 ]]
                      then
                         processBatchContexts
                      fi

		  fi
          fi

  done < "$groupFile"

  else
      echo "No templates found in directory $templateDirectory"
  fi

exit $rc

