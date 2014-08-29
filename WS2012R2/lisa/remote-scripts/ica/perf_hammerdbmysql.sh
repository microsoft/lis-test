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

#######################################################################
#
# This is a test case script designed to run under the LISA test
# framework.  This script will perform the following tasks:
#
#    - Define default test parameters.
#    - Load constants.sh to override default test parameter values.
#    - Verify the HammerDB and MySQL packages are present.
#    - Install MySQL on the host defined by the MYSQL_HOST test parameter.
#    - Start the mysql daemon on the mysql_host.
#    - Use mysqladmin to set/update the expired MySQL password.
#    - Install the HammerDB package on the localhost.
#    - Update the HammerDB configuration settings in the HammerDB config.xml file.
#    - Replace the hammerdb.tcl and hdb_tpcc.tcl files with the
#      modified versions.  Note: the modified versions make calls.
#      to various hammerdb functions to simulate a user running HammerDB.
#    
# Preconditions:
#    This script assumes the following provisioning has been completed on
#    the Linux system under test:
#    - SSH keys have been provisioned on the localhost and on
#      the mysql_host.
#    - The SSH server has strict mode disabled.
#    - The SSH client has strict mode disabled.
#    - If the mysql_host is identified by hostname, then name
#      resolution must be working.
#
# A LISA test case definition would look similar to the following:
#
# <test>
#     <testName>HammerDB</name>
#     <testScript>setupscripts\Perf_HammerDB.ps1</testScript>
#     <files>remote-scripts\ica\perf_hammerdb.sh,tools\lisahdb.tcl,tools\hdb_tpcc.tcl,packages\HammerDB-2.16-Linux-x86-64-Install,packages\MySQL-5.6.16-1.sles11.x86_64.rpm-bundle.tar</files>
#     <onError>Continue</onError>
#     <timeout>3600</timeout>
#     <testParams>
#         <param>HAMMERDB_PACKAGE=HammerDB-2.16-Linux-x86-64-Install</param>
#         <param>HAMMERDB_URL=http://sourceforge.net/projects/hammerora/files/HammerDB/HammerDB-2.16/</param>
#         <param>NEW_HDB_FILE=lisahdb.tcl</param>
#         <param>NEW_TPCC_FILE=hdb_tpcc.tcl</param>
#         <param>RDBMS=MySQL</param>
#         <param>MYSQL_HOST=127.0.0.1</param>
#         <param>MYSQL_PORT=3306</param>
#         <param>MY_COUNT_WARE=2</param>
#         <param>MYSQL_NUM_THREADS=4</param>
#         <param>MYSQL_USER=root</param>
#         <param>MYSQL_PASS=redhat</param>
#         <param>MYSQL_DBASE=tpcc</param>
#         <param>MY_TOTAL_ITERATIONS=1000000</param>
#         <param>MYSQLDRIVER=timed</param>
#         <param>MY_RAMPUP=1</param>
#         <param>MY_DURATION=3</param>
#         <param>MYSQL_PACKAGE="MySQL-5.6.16-1.sles11.x86_64.rpm-bundle.tar</param>
#     </testParams>
# </test>
#
#######################################################################


#
# LISA related constants
#
ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

#
# HammerDB related settings
#
HAMMERDB_VERSION="2.16"
HAMMERDB_PACKAGE="HammerDB-${HAMMERDB_VERSION}-Linux-x86-64-Install"
HAMMERDB_URL="http://sourceforge.net/projects/hammerora/files/HammerDB/HammerDB-${HAMMERDB_VERSION}</param>"
HDB_CONFIG="/usr/local/HammerDB-${HAMMERDB_VERSION}/config.xml"

NEW_HDB_FILE=lisahdb.tcl
NEW_TPCC_FILE=hdb_tpcc.tcl

RDBMS=MySQL                     # Identifies the target database
MYSQL_HOST=127.0.0.1            # IP address of the MySQL host
MYSQL_PORT=3306                 # Port the MySQL server is listening on
MY_COUNT_WARE=2                 # Number of ware houses to create
MYSQL_NUM_THREADS=2             # Number of virtual users to create
MYSQL_USER=root                 # Username to use when connecting to the MySQL server
MYSQL_PASS=redhat               # Password to use when connecting to the MySQL server
MYSQL_DBASE=tpcc                # Which benchmark to run
MY_TOTAL_ITERATIONS=1000000     # Number of iterations for a standard test run
MYSQLDRIVER=timed               # Type of test run
MY_RAMPUP=1                     # Number of minutes of rampup time
MY_DURATION=3                   # Number of minutes to run a 'timed' test

#
# MySQL related settings
#
MYSQL_PACKAGE="MySQL-5.6.16-1.sles11.x86_64.rpm-bundle.tar"


#
# Function definitions
#

#######################################################################
#
# LogMsg()
#
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}


#######################################################################
#
# UpdateTestState()
#
#######################################################################
UpdateTestState()
{
    echo $1 > ~/state.txt
}


#######################################################################
#
# LinuxRelease()
#
#######################################################################
LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        CentOS*)
            echo "CENTOS";;
        *SUSE*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}


#######################################################################
#
# UbuntuInstallMySQL()
#
# Description:
#    Perform distro specific MySQL steps for Ubuntu
#
#######################################################################
UbuntuInstallMySQL()
{
    msg="Error: Ubuntu currently is not supported by this script"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 34
}


#######################################################################
#
# DebianInstallMySQL()
#
# Description:
#    Perform distro specific MySQL steps for Debian
#
#######################################################################
DebianInstallMySQL()
{
    msg="Error: Debian currently is not supported by this script"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 36
}


#######################################################################
#
# RhelInstallMySQL()
#
# Description:
#    Perform distro specific MySQL steps for CentOS and RHEL
#
#######################################################################
RhelInstallMySQL()
{
    msg="Error: CentOS and RHEL currently are not supported by this script"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 32
}


#######################################################################
#
# SlesInstallMySQL()
#
# Description:
#    Perform distro specific MySQL steps for SLES
#
#######################################################################
SlesInstallMySQL()
{
    #
    # Note: A number of steps will use SSH to issue commands to the
    #       MYSQL_HOST.  This requires that the SSH keys be provisioned
    #       in advanced, and strict mode be disabled for both the SSH
    #       server and client.
    #
    LogMsg "Info : SlesInstallMySQL"

    #
    # Sles installs an older version of the MySQL client by default.
    # This older version conflicts with the newer MySQL we will 
    # install.  Quietly remove the older version if it is installed.
    #
    ssh root@${MYSQL_HOST} "zypper --non-interactive remove libmysqlclient18 2>&1"

    #
    # Copy the MySQL package to the MYSQL_HOST, only if it is not the
    # localhost.
    #
    if [ ${MYSQL_HOST} != "127.0.0.1" ]; then
        LogMsg "Info : Copy MYSQL package to mysql_host '${MYSQL_HOST}'"

        scp "./${MYSQL_PACKAGE}" root@${MYSQL_HOST}:
        if [ $? -ne 0 ]; then
            msg="Error: Unable to copy the MYSQL package to host ${MYSQL_HOST}"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 70
        fi
    fi

    #
    # Try to install the MySQL package on the MYSQL_HOST
    #
    # Note: This requires the following:
    #       - The MySQL package is the correct package for the Linux distributioin.
    #       - There is not a mysql client already installed on the MYSQL_HOST.
    #         If there is a MySQL client already installed, the MYSQL install will
    #         most likely fail with a conflict error.
    #       
    LogMsg "Info : Install the MySQL package"

    LogMsg "Info : Deleting old MySQL rpm files"
    ssh root@${MYSQL_HOST} "rm -f ~/MySQL*.rpm"

    LogMsg "Info : Extracting the ${MYSQL_PACKAGE} package"
    ssh root@${MYSQL_HOST} "tar -xf ${MYSQL_PACKAGE}"

    LogMsg "Info : Installing MySQL"
    ssh root@${MYSQL_HOST} "rpm -i MySQL*.rpm"
    if [ $? -ne 0 ]; then
        msg="Error: Unable to install the MySQL packages"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 80
    fi

    #
    # Start the MySQL daemon
    #
    LogMsg "Info : Starting the MySQL daemon"

    #
    # The command "service mysql start" does not work until after a reboot.
    # We need to start the mysql daemon now so the expired password can be
    # reset.  The following is a hack to start the mysql daemon.
    # We need to revisit this later.
    #
    # Create a script that starts MySQL and can be submitted to ATD
    #
    echo "#!/bin/bash" > /root/runmysql.sh
    echo "mysqld_safe" >> /root/runmysql.sh
    chmod 755 /root/runmysql.sh
    scp /root/runmysql.sh root@${MYSQL_HOST}:

    ssh root@${MYSQL_HOST} "service atd start"

    ssh root@${MYSQL_HOST} "at -f /root/runmysql.sh now"
    if [ $? -ne 0 ]; then
        msg="Error: Unable to start the MySQL daemon"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 90
    fi

    #
    # Give MySQL a few seconds to start
    #
    LogMsg "Info : sleep for a few seconds so mysqld can start"
    sleep 10

    #
    # MySQL sets the password for the root user as expired.  The current, expired, password
    # is stored in a file named ~/.mysql_secret.  Extract the expired password from the
    # .mysql_secret file, and then use mysqladmin to reset the password to value specified
    # in the test parameter MYSQL_PASS
    #
    LogMsg "Info : Updating the MySQL expired password"
    expiredPasswd=$(cat ~/.mysql_secret | cut -d : -f 4 | cut -d ' ' -f 2)
    LogMsg "Expired password: '${expiredPasswd}'"
    LogMsg "New password:     '${MYSQL_PASS}'"

    ssh root@${MYSQL_HOST} "mysqladmin -uroot -p${expiredPasswd} PASSWORD $MYSQL_PASS"
    if [ $? -ne 0 ]; then
        msg="Error: Unable to reset expired password for root"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 100
    fi

    #
    # Add an export LD_LIBRARY_PATH to the .bashrc file
    #
    LogMsg "Info : Updating .bashrc"
    clientPath=/usr/lib64/libmysqlclient.so.18
    if [ ! -e $clientPath ]; then
        LogMsg "Info : Searching for libmysqlclient.so.18"
        clientPath=$(find / -name "libmysqlclient.so.18")
        if [ -z ${clientPath} ]; then
            msg="Error: The MySQL client library is not installed"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 50
        fi
    fi

    dirPath=$(dirname ${clientPath})
    grep ${dirPath} ~/.bashrc
    if [ $? -ne 0 ]; then
        LogMsg "Info : Adding LD_LIBRARY_PATH to .bashrc"
        echo "export LD_LIBRARY_PATH=${dirPath}" >> ~/.bashrc
    fi
}


#######################################################################
#
# Main script body
#
#######################################################################

#
# Let the LISA framework know we are running
#
cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting test"

#
# Delete any old summary.log file
#
LogMsg "Delete any old summary.log files"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

#
# Source the constants.sh file
#
LogMsg "Sourcing constants.sh"
if [ ! -e ~/constants.sh ]; then
    msg="Error: ~/constants.sh does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

. ~/constants.sh

#
# Make sure we have the MySQL package, then install it on the
# host defined by the MYSQL_HOST test parameter
#
LogMsg "Info : Checking if MYSQL package '${MYSQL_PACKAGE}' exists"

if [ ! -e "./${MYSQL_PACKAGE}" ]; then
    msg="Error: The package '${MYSQL_PACKAGE}' is not present"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi

#
# Install MySQL - this has distro specific behavior
#
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "RHEL")
        RhelInstallMySQL
    ;;
    "UBUNTU")
        UbuntuInstallMySQL
    ;;
    "DEBIAN")
        DebianInstallMySQL
    ;;
    "SLES")
        SlesInstallMySQL
    ;;
     *)
        msg="Error: Distro '${distro}' not supported"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState "TestAborted"
        exit 1
    ;; 
esac

#
# Now install HammerDB.  This is not distro sensitive.
#

#
# If the HammerDB package is not present, try downloading it
#
if [ ! -e "${HAMMERDB_PACKAGE}" ]; then
    LogMsg "HammerDB package not found.  Attempting to download it"

    wget "${HAMMERDB_URL}/${HAMMERDB_PACKAGE}"
    if [ $? -ne 0 ]; then
        msg="Error: unable to download ${HAMMERDB_PACKAGE}"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 30
    fi
fi

#
# Double check that we have the package
#
if [ ! -e "./${HAMMERDB_PACKAGE}" ]; then
    msg="Error: The HammerDB package was not copied to this system"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi

#
# Make sure the Hammer installation package can be run
# 
chmod 755 ./${HAMMERDB_PACKAGE}

#
# Install Hammer DB to default location (/usr/local/HammerDB-2.16)
#
LogMsg "Installing HammerDB package"

chmod 755 ./${HAMMERDB_PACKAGE}
./${HAMMERDB_PACKAGE} --mode silent

if [ $? -ne 0 ]; then
    msg="Error: Unable to install ${HAMMERDB_PACKAGE}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 40
fi

#
# Update the HammerDB config.xml file.
#
if [ ! -e "${HDB_CONFIG}" ]; then
    msg="Error: The HammerDB config file does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 50
fi

sed -i "/<rdbms>/c\    <rdbms>$RDBMS</rdbms>" $HDB_CONFIG
sed -i "/<mysql_port>/c\        <mysql_port>$MYSQL_PORT</mysql_port>" $HDB_CONFIG
sed -i "/<my_count_ware>/c\            <my_count_ware>$MY_COUNT_WARE</my_count_ware>" $HDB_CONFIG
sed -i "/<mysql_num_threads>/c\            <mysql_num_threads>$MYSQL_NUM_THREADS</mysql_num_threads>" $HDB_CONFIG
sed -i "/<mysql_user>/c\            <mysql_user>$MYSQL_USER</mysql_user>" $HDB_CONFIG
sed -i "/<mysql_pass>/c\            <mysql_pass>$MYSQL_PASS</mysql_pass>" $HDB_CONFIG
sed -i "/<mysql_dbase>/c\            <mysql_dbase>$MYSQL_DBASE</mysql_dbase>" $HDB_CONFIG
sed -i "/<my_total_iterations>/c\            <my_total_iterations>$MY_TOTAL_ITERATIONS</my_total_iterations>" $HDB_CONFIG
sed -i "/<mysqldriver>/c\            <mysqldriver>$MYSQLDRIVER</mysqldriver>" $HDB_CONFIG
sed -i "/<my_rampup>/c\            <my_rampup>$MY_RAMPUP</my_rampup>" $HDB_CONFIG
sed -i "/<my_duration>/c\            <my_duration>$MY_DURATION</my_duration>" $HDB_CONFIG

#
# Cat the config file so it appears in the log file
#
LogMsg "Displaying HammerDB config file"
#cat $HDB_CONFIG

#
# Replace the modified hammerdb files with ones that will
# automatically run a test.
#
LogMsg "Info : replace hammerdb files with modified files"
if [ ! -e $NEW_HDB_FILE ]; then
    msg="Error: The new hammerdb file '${NEW_HDB_FILE}' does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 110
fi

if [ ! -e $NEW_TPCC_FILE ]; then
    msg="Error: The new tpcc file '${NEW_TPCC_FILE}' does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 120
fi

cp $NEW_HDB_FILE /usr/local/HammerDB-${HAMMERDB_VERSION}/
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy new hammerdb.tcl file to HammerDB directory"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi

cp $NEW_TPCC_FILE /usr/local/HammerDB-${HAMMERDB_VERSION}/hdb-components/hdb_tpcc.tcl
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy new tpcc file to the hdb-components directory"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 140
fi

#
# Make sure the new file has permissions to run
#
chmod 755 /usr/local/HammerDB-${HAMMERDB_VERSION}/${NEW_HDB_FILE}

#
# Setup the root user for autologin
#
LogMsg "Info : configuring Display Manager to autologin root"
sed -i 's/DISPLAYMANAGER_AUTOLOGIN=""/DISPLAYMANAGER_AUTOLOGIN="root"/g' /etc/sysconfig/displaymanager

#
# Setup HammerDB for autorun when root is logged on
#
LogMsg "Info : Create the /root/launchhammerdb.sh script"

echo "#!/bin/bash" > /root/launchhammerdb.sh
echo "cd /usr/local/HammerDB-${HAMMERDB_VERSION}" >> /root/launchhammerdb.sh
echo "./${NEW_HDB_FILE}" >> /root/launchhammerdb.sh
chmod 755 /root/launchhammerdb.sh

LogMsg "Info : Create the autostart file"
AUTOSTART=/root/.config/autostart/hammerdb.desktop
mkdir /root/.config/autostart
echo "[Desktop Entry]"                 >  $AUTOSTART
echo "X-SuSE-translate=true"           >> $AUTOSTART
echo "GenericName=HammerDB"            >> $AUTOSTART
echo "Name=HammerDB TPCC Benchmark"    >> $AUTOSTART
echo "Comment=GUI Benchmark tool"      >> $AUTOSTART
echo "TryExec=/root/launchhammerdb.sh" >> $AUTOSTART
echo "Exec=/root/launchhammerdb.sh"    >> $AUTOSTART
echo "Icon=utilities-terminal"         >> $AUTOSTART
echo "Type=Application"                >> $AUTOSTART
echo "StartupNotify=true"              >> $AUTOSTART

#
# If we made it here, everything worked.
# Indicate success and exit
#
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0
