#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

#   This script drives the repository server.  It performs the following
#   tasks:
#     1. For each Linux kernel project listed in the linuxProjects.txt
#        file, pull down a copy of the kernel source tree.
#
#     2. TAR up the kernel source tree in a tar archive.
#
#     3. Name the TAR ball <project>-<date>.tar.bz2
#        For example, if the project was LinuxNext, and the
#        tarball was created on Nov 5, 2010, the tar ball
#        will be named
#            LinuxNext-20101105.tar.bz2
#
#    4.  Update the "current link to the new tarball.  For
#        each project, there is a current link.  For linuxNext
#        the link is:  linuxNextCurrent.tar.bz2
#        This link is updated each night to point to the most
#        recent tarball for the project.
#
#    5. Delete the directory tree of the kernel source tree just pulled
#       down.
#
#    6. Any archives files older than $cutoffDays old, delete the archive 
#       file.
#
# Usage:
#   The command line syntax is:
#     ./repository.sh -d debugLevel -l logFilename -c cutoffDays
#                     -f repositoryFile -r repositoryDir
#   Where:
#     debuglevel	is the level of detail to log into the log file.
#
#     cutoffDays	Is the number of days to keep old tar
#			archives.
#
#     repositoryFile	The file that contains information on which
#			Linux kernel projects to pull down and
#			archive.
#
#     repositoryDir	Is the directory where the repository file,
#			tar archives, and the repository log file
#			are stored.

# Constants
WARN="Warning:"
INFO="info   :"
ERR="ERROR  :"

#
# Who to send e-mail messages to
#
TO="v-ampaw@microsoft.com"

#
# Set default values
#
dbgLevel=5
logLevel=6
repositoryFile="linuxProjects.txt"
repositoryDir="/icaRepository"
cutoffDays=10

now=`date "+%Y%m%d-%H%M%S"`
logFile="${now}.log"
EMAIL_FILE="emailMsg.txt"
withErrors=0


Usage()
{
    echo "repository -d debugLevel -l logFilename -c cutoffDays"
    echo "           -f repositoryFile -r repositoryDirectory"
    echo ""
    exit 1
}

dbgPrint()
{
    if [ $1 -le ${dbgLevel} ]; then
        echo "$2"
    fi
}

logMsg()
{
    if [ $1 -le ${logLevel} ]; then
        dateTime=`date "+%D %T"`
        echo "${dateTime} : $2" >> ${repositoryDir}/logs/${logFile}
    fi
    dbgPrint $1 "$2"
}

#
# InitDirs
#
# Description:
#    Create the directories used by this script.
#
InitDirs()
{
    if [ ! -e ${repositoryDir} ]; then
        echo "ERROR: repository directory does not exist.  Exiting." >> $EMAIL_FILE
        return 20
    fi

    if [ ! -d ${repositoryDir} ]; then
        echo "ERROR: the file '${repositoryDir}' is not a directory.  Exiting." >> $EMAIL_FILE
        return 30
    fi

    if [ ! -e ${repositoryDir}/logs ]; then
        mkdir ${repositoryDir}/logs
        if [ 0 -ne $? ]; then
            echo "ERROR: unable to create the ${repositoryDir}/logs directory." $EMAIL_FILE
            return 40
        fi
    fi

    if [ ! -e ${repositoryDir}/archives ]; then
        mkdir ${repositoryDir}/archives
        if [ 0 -ne $? ]; then
            echo "ERROR: unable to create the ${repositoryDir}/archives directory." >> EMAIL_FILE
            return 50
        fi
    fi

    return 0
}


#
# GetArchive
#
# Description:
#    Do a GIT checkout of a particular kernel source tree, tar the source tree up into
#    a tarball, and then move the tarball to the archives directory.
#
GetArchive()
{
    rootDir="linux-next"


    

    logMsg 3 "${INFO} Removing old linuxNextRCCurrent.tar.bz2."
    rm ./linuxNextRCCurrent.tar.bz2
    logMsg 3 ""

    cd ${rootDir}
    logMsg 3 "${INFO} Checking out latest Linux-Next RC kernel : $1"
    git checkout $1
    if [ 0 -ne $? ]; then
	echo "ERROR: Failed to checkout RC kernel : $1"
	withErrors=1
	retVal=70
    fi
    cd ..
    logMsg 3 "${INFO} Checkout succeeded : $1"
    logMsg 3 "${INFO} Create new tar file for linuxNextRCCurrent"
    logMsg 5 "${INFO} tar -cjf linuxNextRCCurrent.tar.bz2 ${rootDir}"
    tarFile="linuxNextRCCurrent.tar.bz2"
    tar -cjf ${tarFile} ${rootDir}
    if [ 0 -ne $? ]; then
        logMsg 1 "${ERR} Unable to create tar file for linuxNextRCCurrent"
        withErrors=1
        retVal=80
    fi

#        logMsg 3 "${INFO} Deleting the ${project}Current.tar.bz2 link."

#        logMsg 3 "${INFO} Creating link ${project}Current.tar.bz2"
#        logMsg 5 "${INFO} ln -s archives/${tarFile} archives/${project}Current.tar.bz2"
#        ln -s ${repositoryDir}/archives/${tarFile} ${repositoryDir}/archives/${project}Current.tar.bz2
#        if [ 0 -ne $? ]; then
#            logMsg 1 "${ERR} unable to create ${project}Current.tar.bz2 link."
#            withErrors=1
#            retVal=100
#  fi
   # fi

    return ${retVal}

}

SendEMail()
{
    if [ 0 -ne ${withErrors} ]; then
        subject="Repository Server - ERRORS on ${now} : $testRCKernel"
        logMsg 3 "Repository Server - ERRORS on ${now}:$testRCKernel"
    else
        subject="Repository Server - Success on ${now} : $testRCKernel"
        logMsg 3 "Repository Server - Success on ${now} : $testRCKernel"
    fi

    # Attach the log file and send e-mail
   mutt -x -s "${subject}" -a ${repositoryDir}/logs/${logFile} -- $TO < ${repositoryDir}/scripts/$EMAIL_FILE
}

UpdateStable()
{
    #
    # Find the latest stable tarball and download if necessary
    #
    rm -f index.html*
    wget http://www.kernel.org/pub/linux/kernel/v2.6/

    LATEST_STABLE=`cut -d \" -f 2 index.html | grep "^linux*.*bz2$" | sort -t . -s -g | tail -n 1`
    logMsg 1  "${INFO} Latest stable tarball = ${LATEST_STABLE}"

    ls -1 ${repositoryDir}/archives/${LATEST_STABLE}
    if [ $? -eq 0 ]; then
        logMsg 1 "${INFO} We have the latest stable"
    else
        logMsg 1 "${INFO} downloading ${LATEST_STABLE}"
        wget http://www.kernel.org/pub/linux/kernel/v2.6/$LATEST_STABLE
        mv ${LATEST_STABLE} ${repositoryDir}/archives/${LATEST_STABLE}

        logMsg 3 "${INFO} Linking ${LATEST_STABLE} to linuxStableCurrent.tar.bz2"
        rm -f ${repositoryDir}/archives/linuxStableCurrent.tar.bz2
        ln -s ${repositoryDir}/archives/${LATEST_STABLE} ${repositoryDir}/archives/linuxStableCurrent.tar.bz2
    fi

    #
    # Clean up
    #
    rm -f index.html*
}


#####################################################################
#
# Main body of script
#
#####################################################################


#
# Parse command line options

echo "Repository Server - ${now}" > $EMAIL_FILE
echo "Linux-next RC kernel update status" >> $EMAIL_FILE

while getopts :d:l:f:r:c opt
do
    case ${opt} in
    d)  logLevel=${OPTARG}
        ;;
    f)  repositoryFile=${OPTARG}
        ;;
    r)  repositoryDirectory=${OPTARG}
        ;;
    c)  cutoffDays=${OPTARG}
        ;;
    '?') echo "$0: invalid option -${OPTARG}" ?&2
         Usage
         echo "invalid option '${OPTARG} while parsing command line options" >> $EMAIL_FILE
         withErrors=1
         SendEMail
         exit 10
         ;;
    esac
done
shift $((OPTIND -1))

# Setup the directory structure if it does not already exist.
logMsg 3 "${INFO} Initializing directories"

#Source constant file
   . ~/constant.sh
if [ 0 -ne $? ]; then
    logMsg 3 "ERROR: Unable to source the constant.sh file"
    exit
fi

echo "Linux-next RC kernel : $testRCKernel" >> $EMAIL_FILE
InitDirs
if [ 0 -ne $? ]; then
    echo "ERROR: unable to create repository directory structure.  Exiting." >> $EMAIL_FILE
    withErrors=1
    SendEMail
    exit 60
fi

cd ${repositoryDir}/archives

logMsg 3 "${INFO} logFile = ${logFile}"
logMsg 3 "${INFO} repository dir  = ${repositoryDir}"
logMsg 3 "${INFO} RC kernel to checkout  = ${testRCKernel}"

# setup proxy for corp net
export http_proxy="http://itgproxy:80"

today=`date "+%Y%m%d"`

#

    logMsg 3 "${INFO} getting archive ${testRCKernel}"
    GetArchive ${testRCKernel}
    if [ 0 -ne $? ]; then
        logMsg 1 "${ERR} The project ${testRCKernel} failed."
        withErrors=1
    fi

# Note: The dates are formated as string of the format:  yyyymmddhhMMss
#       This allows determining if one date is more recent than another
#       by using simple string comparisons.  A string that is greater
#       than another string is a more recent date.  This avoids any
#       date computations.

#
# Clean up the archives directory
#
#logMsg 1 ""
#logMsg 1 "${INFO} Cleaning up old tar files."

#tarFiles=`ls -1 ${repositoryDir}/archives/*.tar.bz2 | awk '/^linu.[^-]/ {print $1}'`
#cutoffDate=`date -d "-${cutoffDays} day" "+%Y%m%d"`
#
#for file in ${tarFiles}
#do
#    tarDate=`date -r ${file} +%Y%m%d`
#
#    logMsg 5 "${INFO} tar file     = ${file}"
#    logMsg 5 "${INFO}   tarDate    = ${tarDate}"
#    logMsg 5 "${INFO}   cutoffDate = ${cutoffDate}"
#
#    if [ $tarDate -lt $cutoffDate ]; then
#        logMsg 1 "${INFO} Deleting expired tar file ${file}"
#        rm -f ${file}
#    fi
#done
#
#
# Clean up the logs directory
#
#logMsg 1 ""
#logMsg 1 "${INFO} Cleaning up old log files."
#
#logFiles=`ls -1 ${repositoryDir}/logs/*.log`
#cutoffDate=`date -d "-${cutoffDays} day" "+%Y%m%d"`
#
#for file in ${logFiles}
#do
#    logDate=`date -r ${file} +%Y%m%d`
#
#    logMsg 5 "${INFO} log file     = ${file}"
#    logMsg 5 "${INFO}   logDate    = ${logDate}"
#    logMsg 5 "${INFO}   cutoffDate = ${cutoffDate}"
#
#    if [ $logDate -lt $cutoffDate ]; then
#        logMsg 1 "${INFO} Deleting expired log file ${file}"
#        rm -f ${file}
#    fi
#done
#
##
# Update the stable archive if a newer one is out
#
#UpdateStable

SendEMail

