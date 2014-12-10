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

# This script installs LIS drivers
# Uses LIS tarballs available in the repository
# Need more generalization to support LIS versions older than 3.3
# XML element to execute this test :
#	<test>
#            <testName>Install-LIS</testName>
#            <snapshotname>ICABase</snapshotname>
#            <testScript>INSTALL-LIS-Distro.sh</testScript>
#            <files>remote-scripts/ica/INSTALL-LIS-Distro.sh</files>
#            <timeout>18000</timeout>
#            <testparams>
#                <param>TARBALL=lis33.tar.gz</param>
#                <param>REPOSITORY_SERVER=10.200.49.171</param>
#                <param>REPOSITORY_PATH=/icaRepository/LIS</param>
#				<param>TC_COUNT=BVT-15</param>
#				<param>MODE=rpm</param>
# 	    </testparams>
#	    <onError>Continue</onError>
#        </test>
#	<test>

DEBUG_LEVEL=3


dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    echo "ERROR: Unable to source the config file."
    exit 1
fi

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

ScriptInstall()
{
	dbgprint 0  "**************************************************************** "
    dbgprint 0  "LIS Script installation"
    dbgprint 0  "*****************************************************************"

	./install.sh
	sts=$?
	if [ 0 -ne ${sts} ]; then
		dbgprint 0 "Execution of install script failed: ${sts}" 
		dbgprint 0 "Aborting test."
		UpdateTestState "TestFailed"
		UpdateSummary "Execution of install script failed: ${sts}"
		UpdateSummary "LIS installation : Failed"
	    exit 0
	else
		UpdateSummary "LIS installation : Success"
	fi
	
}

RPMInstall ()
{
   
    dbgprint 0  "**************************************************************** "
    dbgprint 0  "LIS RPM installation"
    dbgprint 0  "*****************************************************************"

    # Determine kernel architecture version
    osbit=`uname -m`

    #Selecting appropriate rpm, 64 bit rpm for x86_64 based VM
    if [ "$osbit" == "x86_64" ]; then
       {
              kmodrpm=`ls kmod-microsoft-hyper-v-*.x86_64.rpm`
              msrpm=`ls microsoft-hyper-v-*.x86_64.rpm`
       }
    elif [ "$osbit" == "i686" ]; then
       {
              kmodrpm=`ls kmod-microsoft-hyper-v-*.i686.rpm`
              msrpm=`ls microsoft-hyper-v-*.i686.rpm`
       }
    fi

    #Making sure both rpms are present

    if [ "$kmodrpm" != "" ] && [ "$msrpm" != ""  ]; then
       dbgprint 0 "Installing the Linux Integration Services for Microsoft Hyper-V..."
       rpm -ivh --nodeps $kmodrpm
       kmodexit=$?
       if [ "$kmodexit" == 0 ]; then
              rpm -ivh --nodeps $msrpm
              msexit=$?
              if [ "$msexit" != 0 ]; then
                    dbgprint 0 "Microsoft-Hyper-V RPM installation failed, Exiting."
	                UpdateSummary "RPM installation failed"
	                UpdateTestState "TestFailed"
					 exit 1;
              else
                     dbgprint 0 " Linux Integration Services for Hyper-V has been installed. Please reboot your system."
					 UpdateSummary "LIS RPM installation : Success"
              fi
       else
              dbgprint 0 "Kmod RPM installation failed, Exiting."
			  UpdateSummary "RPM installation failed"
	          UpdateTestState "TestFailed"
              exit 1
       fi
    else
       dbgprint 0 "RPM's are missing"
	   UpdateSummary "RPM installation failed"
	   UpdateTestState "TestFailed"
       exit 1
    fi

}


if [ ! ${TARBALL} ]; then
    dbgprint 0 "The TARBALL variable is not defined."
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 20
fi

if [ ! ${TC_COUNT} ]; then
    dbgprint 0 "The TC_COUNT variable is not defined."
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 30
fi
if [ ! ${MODE} ]; then
    dbgprint 0 "The MODE variable is not defined."
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 30
fi



UpdateSummary "Covers ${TC_COUNT}"
UpdateSummary "TARBALL : ${TARBALL}"

if [ ! /etc/redhat-release ]; then
    dbgprint 0 "Not supported distro for LIS installation"
	UpdateSummary "Not supported distro for LIS installation"
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 45
fi

#
# Copy the tarball from the repository server
#
dbgprint 1 "copying tarball : ${TARBALL} from repository server : ${REPOSITORY_SERVER}"
#scp -i .ssh/ica_repos_id_rsa root@${REPOSITORY_SERVER}:${REPOSITORY_PATH}/${TARBALL} .
mkdir nfs
mount ${REPOSITORY_SERVER}:${REPOSITORY_PATH} ./nfs
if [ -e ./nfs/${TARBALL} ]; then
    cp ./nfs/${TARBALL} .

else

    dbgprint 0 "Tarball ${TARBALL} not found in repository."
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 40
fi

umount ./nfs
rm -rf ./nfs



dbgprint 3 "Extracting LIS sources from ${TARBALL}"

tar -xmf ${TARBALL}
sts=$?
if [ 0 -ne ${sts} ]; then
    dbgprint 0 "tar failed to extract the LIS from the tarball: ${sts}" 
    UpdateTestState "TestAborted"
    exit 40
fi
ROOTDIR="LIS"


OSInfo=(`cat /etc/redhat-release | cut -f 1 -d ' '`)
if [ $OSInfo == "CentOS" ]; then
    OSversion=(`cat /etc/redhat-release | cut -f 3 -d ' '`)
elif [ $OSInfo == "Red" ]; then
    OSversion=(`cat /etc/redhat-release | cut -f 7 -d ' '`)
fi

#Arch=(`uname -a | cut -f 12 -d ' '`)
case "$OSversion" in
"5.5")
    DIR="/RHEL55/"
	;;
"5.6")
    DIR="/RHEL56/"
	;;
"5.7")
    DIR="/RHEL57/"
	;;
"5.8")
    DIR="/RHEL58/"
	;;
"6.0" )
    DIR="/RHEL6012/"
	;;
"6.1" )
    DIR="/RHEL6012/"
	;;
"6.2" )
    DIR="/RHEL6012/"
	;;
"6.3")
    DIR="/RHEL63/"
	;;
*)
    dbgprint 0 "Distro Version not supported for LIS installation"
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 45
	;;
esac

# if [ $Arch -eq "x86" ]; then
    # $ROOTDIR = $ROOTDIR + "x86"
# fi
# else
	# $ROOTDIR = $ROOTDIR + "x86_64"
	

if [ ! -e ${ROOTDIR} ]; then
    dbgprint 0 "The tar file did not create the directory: ${ROOTDIR}"
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 50
fi

if [ -e $ROOTDIR/install.sh ]; then
    FinalDIR=$ROOTDIR  
else
    FinalDIR=$ROOTDIR$DIR
fi

cd $FinalDIR

if [ ${MODE} == "rpm" ]; then
    RPMInstall
else
    if [ ${MODE} == "script" ]; then
    ScriptInstall
    else
    dbgprint 0 "Invalid Installation Mode"
	UpdateSummary "Invalid Installation Mode"
	UpdateTestState "TestAborted"
	exit 10
	fi
fi

UpdateSummary "OS Version : $OSversion "
UpdateSummary "Kernel Version : `uname -r` "
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"