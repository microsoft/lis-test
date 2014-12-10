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
#/bin/bash
# LIS_Uninstall.sh
# This script installs LIS drivers
#Uses LIS tarballs available in the repository
#Need more generalization to support LIS versions older than 3.3
#XML element to execute this test :
#	<test>
#            <testName>UnInstall-LIS</testName>
#            <snapshotname>ICABase</snapshotname>
#            <testScript>LIS_UnInstall.sh</testScript>
#            <files>remote-scripts/ica/LIS_UnInstall.sh</files>
#            <timeout>18000</timeout>
#            <testparams>
#				<param>TC_COUNT=BVT-33</param>
# 	    </testparams>
#	    <onError>Continue</onError>
#        </test>


DEBUG_LEVEL=3


dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

UnInstallLIS ()
{
   
    dbgprint 0  "**************************************************************** "
    dbgprint 0  "LIS Uninstallation"
    dbgprint 0  "*****************************************************************"

    # Determine kernel architecture version
    osbit=`uname -m`

    #Selecting appropriate rpm, 64 bit rpm for x86_64 based VM
    if [ "$osbit" == "x86_64" ]; then
       {
              kmodrpm=`ls kmod-microsoft-hyper-v-*.x86_64.rpm | sed 's#.rpm##g'`
              msrpm=`ls microsoft-hyper-v-*.x86_64.rpm | sed 's#.rpm##g'`
       }
    elif [ "$osbit" == "i686" ]; then
       {
              kmodrpm=`ls kmod-microsoft-hyper-v-*.i686.rpm | sed 's#.rpm##g'`
              msrpm=`ls microsoft-hyper-v-*.i686.rpm | sed 's#.rpm##g'`
       }
    fi

    #Making sure both rpms are present

    if [ "$kmodrpm" != "" ] && [ "$msrpm" != ""  ]; then
       dbgprint 0 "Removing the Linux Integration Services for Microsoft Hyper-V..."
       rpm -e $msrpm
       msexit=$?
       if [ "$msexit" == 0 ]; then
              rpm -e $kmodrpm
              kmodexit=$?
              if [ "$kmodexit" != 0 ]; then
                    dbgprint 0 "Kmod RPM uninstallation failed, Exiting."
	                UpdateSummary "LIS RPM uninstallation : Failed "
	                UpdateTestState "TestFailed"
					 exit 1;
              else
                     # Remove hda=noprobe hdb=noprobe from grub
					 sed -i 's/hda=.*//' /boot/grub/menu.lst
					 dbgprint 0 " Linux Integration Services for Hyper-V has been removed. Please reboot your system."
					 UpdateSummary "LIS RPM uninstallation : Success"
              fi
       else
			  dbgprint 0 "Microsoft-Hyper-V uninstallation failed, Exiting."
			  UpdateSummary "LIS RPM uninstallation : Failed "
	          UpdateTestState "TestFailed"
              exit 1
       fi
    else
       dbgprint 0 "RPMs are missing"
	   UpdateSummary "LIS RPMs are missings "
	   UpdateTestState "TestAborted"
       exit 1
    fi

}


if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi


#
# Convert any .sh files to Unix format
#

dos2unix -f ~/*.sh > /dev/null  2>&1

# Source the constants file

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    echo "ERROR: Unable to source the constants file."
    exit 1
fi

UpdateTestState "TestRunning"



if [ ! ${TC_COUNT} ]; then
    dbgprint 0 "The TC_COUNT variable is not defined."
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 30
fi

UpdateSummary "Covers ${TC_COUNT}"

if [ ! /etc/redhat-release ]; then
    dbgprint 0 "Not supported distro for LIS uninstallation"
	UpdateSummary "Not supported distro for LIS uninstallation"
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 45
fi

lsmod | grep "hv" 2>&1
sts=$?

if [ $sts -ne 0 ]; then
    dbgprint 0 "Error : LIS is not installed"
	UpdateSummary "Error : LIS is not installed"
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 45
fi

ROOTDIR="LIS"

if [ ! ${ROOTDIR} ]; then
    dbgprint 0 "Error : LIS source tree not found"
	UpdateSummary "Error : LIS source tree not found"
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 45
fi


OSInfo=(`cat /etc/redhat-release | cut -f 1 -d ' '`)
if [ $OSInfo == "CentOS" ]; then
    OSversion=(`cat /etc/redhat-release | cut -f 3 -d ' '`)
elif [ $OSInfo == "Red" ]; then
    OSversion=(`cat /etc/redhat-release | cut -f 7 -d ' '`)
fi

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

if [ -e $ROOTDIR/install.sh ]; then
    FinalDIR=$ROOTDIR  
else
    FinalDIR=$ROOTDIR$DIR
fi

cd $FinalDIR

UnInstallLIS

cd ~
rm -rf $ROOTDIR

echo "#########################################################"
echo "Result : Test Completed Succesfully"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"


