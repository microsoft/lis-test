#!/bin/bash

#######################################################################
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
#######################################################################

#######################################################################
#
# perf_confighadoop
#
# Description:
#    Install and configure Hadoop so the TeraSort benchmark can
#    be run.  Since Hadoop is written in Java, we need to ensure
#    Java is also installed.
#
#    Installing and configuring Hadoop consists of the following
#    steps:
#
#    1. Install a Java JDK
#    2. Download the Hadoop tar.gz archive
#    3. Unpackage the Hadoop archive
#    4. Move the hadoop directory to /usr/local/hadoop
#    5. Update the ~/.bashrc file with hadoop specific exports
#    6. Edit the various hadoop config files
#         hadoop-env.sh
#         core-site.xml
#         yarn-site.xml
#         mapred-site.xml
#         hdfs-site.xml
#    7. Start the Hadoop filesystem
#    8. Start Hadoop
#    9. Start yarn
#   10. Generate content for terasort
#   11. Run terasort
#   
#
#######################################################################


#
# Constants/Globals
#
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during the setup of the test
ICA_TESTFAILED="TestFailed"        # Error occured during the test

CONSTANTS_FILE="/root/constants.sh"
SUMMARY_LOG=~/summary.log

HADOOP_VERSION="2.4.0"
HADOOP_ARCHIVE="hadoop-${HADOOP_VERSION}.tar.gz"
HADOOP_URL="http://apache.cs.utah.edu/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"


#######################################################################
#
# LogMsg()
#
#######################################################################
LogMsg()
{
    echo `date "+%b %d %Y %T"` : "${1}"    # Add the timestamp to the log message
    echo "${1}" >> ~/hadoop.log
}


#######################################################################
#
# UpdateTestState()
#
#######################################################################
UpdateTestState()
{
    echo "${1}" > ~/state.txt
}


#######################################################################
#
# UpdateSummary()
#
#######################################################################
UpdateSummary()
{
    echo "${1}" >> ~/summary.log
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
# ConfigRhel()
#
#######################################################################
ConfigRhel()
{
    LogMsg "ConfigRhel"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        yum -y install java-1.7.0-openjdk
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install Java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
	
    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    LogMsg "Create JAVA_HOME variable"

    javaConfig=`echo "" | update-alternatives --config java | grep "*"`
    tokens=( $javaConfig )
    javaPath=${tokens[2]}
    if [ ! -e $javaPath ]; then
        LogMsg "Error: Unable to find the Java install path"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp=`dirname $javaPath`
    JAVA_HOME=`dirname $temp`
    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    #
    # This is a hack so we can use the same hadoop config on all Linux
    # distros.  With RHEL, localhost fails.  By setting the hostname
    # to localhost, then the default config works in RHEL.
    # Need to revisit this to find a better solution.
    #
    hostname localhost
}


#######################################################################
#
# ConfigSles()
#
#######################################################################
ConfigSles()
{
    LogMsg "ConfigSles"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        zypper --non-interactive install jre-1.7.0
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi

    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    javaConfig=`update-alternatives --config java`
    tempHome=`echo $javaConfig | cut -f 2 -d ':' | cut -f 2 -d ' '`

    if [ ! -e $tempHome ]; then
        LogMsg "Error: The Java directory '${tempHome}' does not exist"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp1=`dirname $tempHome`
    JAVA_HOME=`dirname $temp1`

    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    #
    # Depending on how the user configs the SLES system, we may or may not
    # need the following workaround to allow hadoop to use localhost
    #
    hostname localhost
}


#######################################################################
#
# ConfigUbuntu()
#
#######################################################################
ConfigUbuntu()
{
    LogMsg "ConfigUbuntu"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        apt-get -y install default-jdk
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi

    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    javaConfig=`update-alternatives --config java`
    tempHome=`echo $javaConfig | cut -f 2 -d ':' | cut -f 2 -d ' '`
    if [ ! -e $tempHome ]; then
        LogMsg "Error: The Java directory '${tempHome}' does not exist"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp1=`dirname $tempHome`
    temp2=`dirname $temp1`
    JAVA_HOME=`dirname $temp2`
    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
}


#######################################################################
#
# Main script body
#
#######################################################################

cd /root
UpdateTestState $ICA_TESTRUNNING

#
# Install Java
#
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "RHEL")
        ConfigRhel
    ;;
    "UBUNTU")
        ConfigUbuntu
    ;;
    "DEBIAN")
        LogMsg "Debian is not supported"
        UpdateTestState "TestAborted"
        UpdateSummary "  Distro '${distro}' is not currently supported"
        exit 1
    ;;
    "SLES")
        ConfigSles
    ;;
     *)
        LogMsg "Distro '${distro}' not supported"
        UpdateTestState "TestAborted"
        UpdateSummary " Distro '${distro}' not supported"
        exit 1
    ;; 
esac

#
# Download Hadoop
#
LogMsg "Downloading Hadoop if we do not have a local copy"

if [ ! -e "/root/${HADOOP_ARCHIVE}" ]; then
    LogMsg "Downloading Hadoop from ${HADOOP_URL}"

    wget "${HADOOP_URL}"
    if [ $? -ne 0 ]; then
        LogMsg "Error: Unable to download hadoop from ${HADOOP_URL}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    LogMsg "Hadoop successfully downloaded"
fi

#
# Untar and install Hadoop
#
LogMsg "Extracting the hadoop archive"

tar -xzf ./${HADOOP_ARCHIVE}
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to extract hadoop from its archive"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi    

if [ ! -e "/root/hadoop-${HADOOP_VERSION}" ]; then
    LogMsg "Error: The expected hadoop directory '~/hadoop-${HADOOP_VERSION}' was not created when extracting hadoop"
    UpdateTestState $sICA_TESTFAILED
    exit 1
fi

#
# Move the hadoop directory to where it should be
#
LogMsg "Move the hadoop directory to /usr/local/hadoop"

if [ -e /usr/local/hadoop ]; then
    rm -rf /usr/local/hadoop
fi

mv "/root/hadoop-${HADOOP_VERSION}" /usr/local/hadoop
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to move hadoop to the /usr/local/hadoop directory"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Add Hadoop specific exports to the .bashrc file
#
LogMsg "Check if Hadoop specific exports are in the .bashrc file"

grep -q "Hadoop exports start" ~/.bashrc
if [ $? -ne 0 ]; then
    LogMsg "Hadoop exports not found in ~/.bashrc, adding them"

    echo "" >> ~/.bashrc
    echo "# Hadoop exports start" >> ~/.bashrc
    echo "export JAVA_HOME=${JAVA_HOME}" >> ~/.bashrc
    echo "export HADOOP_INSTALL=/usr/local/hadoop" >> ~/.bashrc
    echo "export PATH=\$PATH:\$HADOOP_INSTALL/bin" >> ~/.bashrc
    echo "export PATH=\$PATH:\$HADOOP_INSTALL/sbin" >> ~/.bashrc
    echo "export HADOOP_MAPRED_HOME=\$HADOOP_INSTALL" >> ~/.bashrc
    echo "export HADOOP_COMMON_HOME=\$HADOOP_INSTALL" >> ~/.bashrc
    echo "export HADOOP_HDFS_HOME=\$HADOOP_INSTALL" >> ~/.bashrc
    echo "export YARN_HOME=\$HADOOP_INSTALL" >> ~/.bashrc
    echo "export HADOOP_COMMON_LIB_NATIVE_DIR=\$HADOOP_INSTALL/lib/native" >> ~/.bashrc
    echo "export HADOOP_OPTS=\"-Djava.library.path=\$HADOOP_INSTALL/lib\"" >> ~/.bashrc
    echo "# Hadoop exports end" >> ~/.bashrc
fi

#
# Sourcing the update .bashrc
#
source ~/.bashrc
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to source .bashrc"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Update the Hadoop config files
#
cd /usr/local/hadoop/etc/hadoop
if [ $? -ne 0 ]; then
    LogMsg "Error: the /usr/local/hadoop/etc/hadoop directory does not exist"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Update JAVA_HOME in hadoop-env.sh
#
LogMsg "Updating hadoop-env.sh"

sed -i "s~export JAVA_HOME=\${JAVA_HOME}~export JAVA_HOME=${JAVA_HOME}~g" ./hadoop-env.sh
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update hadoop-env.sh"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Update the configuration in core-site.xml
#
LogMsg "Updating core-site.xml"

sed -i "s~<configuration>~<configuration>\n    <property>\n        <name>fs.default.name</name>\n        <value>hdfs://localhost:9000</value>\n    </property>~g" ./core-site.xml
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update core-site.xml"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Update the configuration in yarn-site.xml
#
LogMsg "Updating yarn-site.xml"

newConfig="<configuration>\n    <property>\n        <name>yarn.nodemanager.aux-services</name>\n        <value>mapreduce_shuffle</value>\n    </property>\n    <property>\n        <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>\n        <value>org.apache.hadoop.mapred.ShuffleHandler</value>\n    </property>"
sed -i "s~<configuration>~${newConfig}~g" ./yarn-site.xml
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update yarn-site.xml"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Copy mapred-site.xml.template to mapred-site.xml and update the configuration
#
LogMsg "Create mapred-site.xml, and update its configuration"

cp ./mapred-site.xml.template ./mapred-site.xml
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to copy mapred-site.xml.template"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

sed -i "s~<configuration>~<configuration>\n    <property>\n        <name>mapreduce.framework.name</name>\n        <value>yarn</value>\n    </property>~g" ./mapred-site.xml
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update mapred-site.xml"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Create the directories to be used as the nodename and datanode on the local host
#
LogMsg "Creating node and data directories on the localhost"

mkdir -p /usr/local/hadoop_store/hdfs/namenode
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to create the namenode directory"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

mkdir -p /usr/local/hadoop_store/hdfs/datanode
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to create the datanode directory"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Update the hdfs-site.xml
#
LogMsg "Updating hdfs-site.xml"

newConfig="<configuration>\n    <property>\n        <name>dfs.replication</name>\n        <value>1</value>\n    </property>\n    <property>\n        <name>dfs.namenode.name.dir</name>\n        <value>file:/usr/local/hadoop_store/hdfs/namenode</value>\n    </property>\n    <property>\n        <name>dfs.datanode.data.dir</name>\n        <value>file:/usr/local/hadoop_store/hdfs/datanode</value>\n    </property>"
sed -i "s~<configuration>~${newConfig}~g" ./hdfs-site.xml
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update the hdfs-site.xml file"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Format the new Hadoop filesystem
# Note: This only needs to be done the first time
#
LogMsg "Format the Hadoop filesystem"

/usr/local/hadoop/bin/hdfs namenode -format
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to format the Hadoop filesystem"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Create directories used by teragen and terasort
#
LogMsg "Creating directories for us by TeraGen and TeraSort"

mkdir -p /root/genout
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to create the genout directory"
    UupdateTestState $ICA_TESTFAILED
    exit 1
fi

mkdir -p /root/sortout
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to create the sortout directory"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

mkdir -p /root/verout
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to create the verout directory"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

LogMsg "Hadoop setup and config complete.  You need to start"
LogMsg "Hadoop, entry passwords when the keys are generated."
LogMsg "Then start yarn, run TeraGen to generate test content,"
LogMsg "and finally run TeraSort."

UpdateTestState $ICA_TESTCOMPLETED

exit 0

