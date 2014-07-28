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
#    be run.  This script needs to be run on each node in the
#    hadoop cluster.  This script configures a hadoop cluster
#    with minimal security.  Since the intended use of the cluster
#    is for running bench marks, security is not a concern.
#
#    Hadoop is written in Java, so we need to ensure that a
#    Java runtime is also installed.
#
#    Installing and configuring Hadoop consists of the following
#    steps:
#
#     1. Install a Java JDK
#     2. Download the Hadoop tar.gz archive
#     3. Unpackage the Hadoop archive
#     4. Move the hadoop directory to /usr/local/hadoop
#     5. Update the ~/.bashrc file with hadoop specific exports
#     6. Edit the various hadoop config files
#         hadoop-env.sh
#         core-site.xml
#         yarn-site.xml
#         mapred-site.xml
#         hdfs-site.xml
#     7. Format the Hadoop file system
#     8. Start Hadoop
#     9. Start yarn
#    10. Generate content for terasort
#    11. Run terasort
#   
#    This script assumes the test machines which will be used to form
#    the cluster have been provisioned properly.  Provisioning includes:
#
#        Configuring DNS so that each machine in the Hadoop cluster
#        can resolve the name of all the other machine names in the
#        cluster.
#
#        SSH Keys are configured on all machines in the cluster.
#
#        The SSH keys are not password protected.
#
#        The SSH daemon and client are configured with strict mode disabled. 
#
#    This script uses a constants.sh script to read in test parameters.
#    A typical constants.sh will look similar to the following:
#
#        HADOOP_MASTER_HOSTNAME=master
#        RESOURCE_MANAGER_HOSTNAME=master
#        SLAVE_HOSTNAMES="slave1 slave2 slave3"
#        TERAGEN_RECORDS=1000000
#
#######################################################################


#
# Constants/Globals
#
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during the setup of the test
ICA_TESTFAILED="TestFailed"        # Error occurred during the test

CONSTANTS_FILE="/root/constants.sh"
SUMMARY_LOG=~/summary.log

HADOOP_VERSION="2.4.0"
HADOOP_ARCHIVE="hadoop-${HADOOP_VERSION}.tar.gz"
HADOOP_URL="http://apache.cs.utah.edu/hadoop/common/hadoop-${HADOOP_VERSION}/${HADOOP_ARCHIVE}"

CONFIG_SCRIPT="/root/perf_hadoopterasort.sh"


#######################################################################
#
# LogMsg()
#
#######################################################################
LogMsg()
{
    echo `date "+%b %d %Y %T"` : "${1}"    # Add the time stamp to the log message
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
# TimeToSeconds()
#
#######################################################################
TimeToSeconds()
{
    read -r h m s <<< $(echo $1 | tr ':' ' ')
    #echo $(((h*60*60)+(m*60)+s))
    echo `echo "${h}*60*60+${m}*60+${s}" | bc`
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
    #hostname localhost
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
    #hostname localhost
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
# Run Config on Slave nodes
#
#######################################################################
RunConfigOnSlaves()
{
    #
    # This function should only be called by the master.
    # Ensure we are running on the master.
    #


    #
    # Copy the perf_hadoopterasort.sh, constants.sh and hadoop zip (if exists) to each slave.
    # Then chmod the files.  Finally, run the config script on each slave.
    #
    chmod 600 /root/${SLAVE_SSHKEY}

    for slave in $SLAVE_HOSTNAMES
    do
        LogMsg "Info : Running config on slave '${slave}'"

        scp -o StrictHostKeyChecking=no -i /root/${SLAVE_SSHKEY} /root/${HADOOP_ARCHIVE} root@${slave}:
        if [ $? -ne 0 ]; then
            msg="Error: Unable to copy file ${HADOOP_ARCHIVE} to slave ${slave}"
            LogMsg "${msg}"
            echo "${msg}" >> ./summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        scp -o StrictHostKeyChecking=no -i /root/${SLAVE_SSHKEY} ${CONFIG_SCRIPT} root@${slave}:
        if [ $? -ne 0 ]; then
            msg="Error: Unable to copy file ${CONFIG_SCRIPT} to slave ${slave}"
            LogMsg "${msg}"
            echo "${msg}" >> ./summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        ssh -o StrictHostKeyChecking=no -i /root/${SLAVE_SSHKEY} root@${slave} chmod 755 ${CONFIG_SCRIPT}
        if [ $? -ne 0 ]; then
            msg="Error: Unable to chmod 755 script file ${CONFIG_SCRIPT} on slave ${slave}"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        scp -o StrictHostKeyChecking=no -i /root/${SLAVE_SSHKEY} ${CONSTANTS_FILE} root@${slave}:
        if [ $? -ne 0 ]; then
            msg="Error: Unable to copy constants.sh to slave ${slave}"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        ssh -o StrictHostKeyChecking=no -i /root/${SLAVE_SSHKEY} root@${slave} ${CONFIG_SCRIPT}
        if [ $? -ne 0 ]; then
            msg="Error: ${CONFIG_SCRIPT} did not run successfully on slave ${slave}"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

    done
}


#######################################################################
#
# Check Provisioning
#
# Description:
#    All nodes in a Hadoop cluster need to be able to access
#    all cluster nodes by name.  Verify all nodes can ping
#    each other by name.
#
#    
#######################################################################
CheckProvisioning()
{
    #
    # Make sure all nodes can ping all other nodes by name
    #
    LogMsg "Info : Check Provisioning - ping HADOOP_MASTER_HOSTNAME"

    ping -c 1 $HADOOP_MASTER_HOSTNAME
    if [ $? -ne 0 ]; then
        msg="Error: Unable to ping HADOOP_MASTER_HOSTNAME '${HADOOP_MASTER_HOSTNAME}'"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    LogMsg "Info : Check Provisioning - ping RESOURCE_MANAGER__HOSTNAME"

    ping -c 1 $RESOURCE_MANAGER_HOSTNAME
    if [ $? -ne 0 ]; then
        msg="Error: Unable to ping RESOURCE_MANAGER_HOSTNAME '${RESOURCE_MANAGER_HOSTNAME}'"
        LogMsg "${msg}"
        echo "${msg}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    LogMsg "Info : Check Provisioning - ping each slave hostname"

    for host in $SLAVE_HOSTNAMES
    do
        ping -c 1 $host
        if [ $? -ne 0 ]; then
            msg="Error: Unable to ping slave host '${host}'"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    done
}


#######################################################################
#
# Main script body
#
#######################################################################

cd ~

UpdateTestState $ICA_TESTRUNNING
LogMsg "Updated test case state to running"

rm -f ~/summary.log
touch ~/summary.log

if [ -e ${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    errMsg="Error: missing ${CONSTANTS_FILE} file"
    LogMsg "${errMsg}"
    echo "${errMsg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ ! ${HADOOP_MASTER_HOSTNAME} ]; then
    errMsg="The HADOOP_MASTER_HOSTNAME test parameter is not defined"
    LogMsg "${errMsg}"
    echo "${errMsg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ ! ${RESOURCE_MANAGER_HOSTNAME} ]; then
    errMsg="The RESOURCE_MANAGER_HOSTNAME test parameter is not defined"
    LogMsg "${errMsg}"
    echo "${errMsg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ ! ${TERAGEN_RECORDS} ]; then
    LogMsg "Info : TERAGEN_RECORDS not defined in constants.sh"
    TERAGEN_RECORDS=1000000
fi

LogMsg "Info : TERAGEN_RECORDS = ${TERAGEN_RECORDS}"

#
# Check provisioning of the cluster nodes
#
LogMsg "Info : Checking node provisioning"

CheckProvisioning

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
    rm -rf /usr/local/hadoop_store
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
    echo "export HADOOP_HOME=/usr/local/hadoop" >> ~/.bashrc
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

sed -i "s~</configuration>~    <property>~g" ./core-site.xml
echo "        <name>fs.default.name</name>" >> ./core-site.xml
echo "        <value>hdfs://${HADOOP_MASTER_HOSTNAME}:9000</value>" >> ./core-site.xml
echo "    </property>" >> ./core-site.xml
echo "</configuration>" >> ./core-site.xml

if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update core-site.xml"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Update the configuration in yarn-site.xml
#
LogMsg "Updating yarn-site.xml"

sed -i "s~</configuration>~    <property>~g" ./yarn-site.xml

echo "        <name>yarn.nodemanager.aux-services</name>" >> ./yarn-site.xml
echo "        <value>mapreduce_shuffle</value>" >> ./yarn-site.xml
echo "    </property>" >> ./yarn-site.xml
echo "    <property>" >> ./yarn-site.xml
echo "        <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>" >> ./yarn-site.xml
echo "        <value>org.apache.hadoop.mapred.ShuffleHandler</value>" >> ./yarn-site.xml
echo "    </property>" >> ./yarn-site.xml
echo "    <property>" >> ./yarn-site.xml
echo "        <name>yarn.resourcemanager.hostname</name>" >> ./yarn-site.xml
echo "        <value>${RESOURCE_MANAGER_HOSTNAME}</value>" >> ./yarn-site.xml
echo "    </property>" >> ./yarn-site.xml
echo "    <property>" >> ./yarn-site.xml
echo "        <name>yarn.nodemanager.resource.memory-mb</name>" >> ./yarn-site.xml
echo "        <value>8192</value>" >> ./yarn-site.xml
echo "    </property>" >> ./yarn-site.xml
echo "    <property>" >> ./yarn-site.xml
echo "        <name>yarn.scheduler.minimum-allocation-mb</name>" >> ./yarn-site.xml
echo "        <value>512</value>" >> ./yarn-site.xml
echo "    </property>" >> ./yarn-site.xml
echo "</configuration>" >> ./yarn-site.xml

if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update yarn-site.xml"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Copy mapred-site.xml.template to mapred-site.xml and update the configuration
#
LogMsg "Create mapred-site.xml, then update its configuration"

cp ./mapred-site.xml.template ./mapred-site.xml
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to copy mapred-site.xml.template"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

sed -i "s~</configuration>~    <property>~g" ./mapred-site.xml

echo "        <name>mapreduce.framework.name</name>" >> ./mapred-site.xml
echo "        <value>yarn</value>" >> ./mapred-site.xml
echo "    </property>" >> ./mapred-site.xml
echo "</configuration>" >> ./mapred-site.xml

if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update mapred-site.xml"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Create the directories to be used as the nodename and datanode on the local host
#
#LogMsg "Creating node and data directories on the localhost"

#mkdir -p /usr/local/hadoop_store/hdfs/namenode
#if [ $? -ne 0 ]; then
#    LogMsg "Error: Unable to create the namenode directory"
#    UpdateTestState $ICA_TESTFAILED
#    exit 1
#fi

#mkdir -p /usr/local/hadoop_store/hdfs/datanode
#if [ $? -ne 0 ]; then
#    LogMsg "Error: Unable to create the datanode directory"
#    UpdateTestState $ICA_TESTFAILED
#    exit 1
#fi

#
# Update the hdfs-site.xml
#
LogMsg "Updating hdfs-site.xml"

sed -i "s~</configuration>~    <property>~g" ./hdfs-site.xml

echo "        <name>dfs.replication</name>" >> ./hdfs-site.xml
echo "        <value>1</value>" >> ./hdfs-site.xml
echo "    </property>" >> ./hdfs-site.xml
echo "    <property>" >> ./hdfs-site.xml
echo "        <name>dfs.namenode.name.dir</name>" >> ./hdfs-site.xml
echo "        <value>file:/usr/local/hadoop_store/hdfs/namenode</value>" >> ./hdfs-site.xml
echo "    </property>" >> ./hdfs-site.xml
echo "    <property>" >> ./hdfs-site.xml
echo "        <name>dfs.datanode.data.dir</name>" >> ./hdfs-site.xml
echo "        <value>file:/usr/local/hadoop_store/hdfs/datanode</value>" >> ./hdfs-site.xml
echo "    </property>" >> ./hdfs-site.xml
echo "</configuration>" >> ./hdfs-site.xml

if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to update the hdfs-site.xml file"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Update the slaves file if the SLAVE_HOSTNAMES test parameter is defined
#
if [ "${SLAVE_HOSTNAMES:-undefined}" != "undefined" ]; then
    rm -f ./slaves
    touch ./slaves
    for host in $SLAVE_HOSTNAMES
    do
        echo $host >> ./slaves
    done
fi

#
# Format the new Hadoop file system
# Note: This only needs to be done the first time and only on the master.
#
LogMsg "Format the Hadoop file system"
hname=$(hostname)

if [ "${hname}" = "${HADOOP_MASTER_HOSTNAME}" ]; then
    #
    # Run the config script on each slave.  Then format hdfs.
    #
    LogMsg "Info : Run Config on each slave"
    RunConfigOnSlaves

    /usr/local/hadoop/bin/hdfs namenode -format
    if [ $? -ne 0 ]; then
        LogMsg "Error: Unable to format the Hadoop file system"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
else
    LogMsg "Info : Not on master, file system will not be formatted"
fi

#LogMsg "  Hadoop setup and config complete.  You need to start"
#LogMsg "  Hadoop, entry passwords when the keys are generated."
#LogMsg "  Then start yarn, run TeraGen to generate test content,"
#LogMsg "  and finally run TeraSort."

#
# If on the master, start the various Hadoop components, then
# generate the test data, sort the test data, and finally,
# compute the sort time.
#
if [ "${hname}" = "${HADOOP_MASTER_HOSTNAME}" ]; then
    #
    # Make sure we have the changes added to .bashrc
    #
    source ~/.bashrc

    #
    # Start the Hadoop components
    #
    LogMsg "Info : Starting DFS"
    start-dfs.sh
    if [ $? -ne 0 ]; then
        msg="Error: Unable to start DFS"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    LogMsg "Info : Starting Yarn"
    start-yarn.sh
    if [ $? -ne 0 ]; then
        msg="Error: Unable to start Yarn"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    #
    # Create the test data, then sort it
    #
    LogMsg "Info : Run TeraGen to create test data"
    LogMsg "Info : TeraGen to create ${TERAGEN_RECORDS} records"

    hadoop jar /usr/local/hadoop/share/hadoop/mapreduce/hadoop-*examples*.jar teragen $TERAGEN_RECORDS /data/genout
    if [ $? -ne 0 ]; then
        msg="Error: Unable to generate test data"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    LogMsg "Info : Running terasort to sort test data"
    hadoop jar /usr/local/hadoop/share/hadoop/mapreduce/hadoop-*examples*.jar terasort /data/genout /data/sortout 2&> ~/terasort.log
    if [ $? -ne 0 ]; then
        msg="Error: Unable to sort the test data"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    #
    # Cat the terasort.log file so its contents show up in the test case log file
    #
    LogMsg "Info : outputing the terasort.log file"
    cat ~/terasort.log

    #
    # Compute the sort time
    #
    LogMsg "Info : Computing sort time"
    startStr=`grep 'INFO terasort.TeraSort: starting' ~/terasort.log`
    endStr=`grep   'INFO terasort.TeraSort: done' ~/terasort.log`

    startStr=`echo $startStr | cut -f 2 -d ' '`
    stopStr=`echo $endStr   | cut -f 2 -d ' '`

    startSeconds=$(TimeToSeconds $startStr)
    stopSeconds=$(TimeToSeconds $stopStr)

    timeInSeconds=$((stopSeconds-$startSeconds))
    LogMsg "Info : TeraSort sort time in seconds: ${timeInSeconds}"
    echo "Sort time in seconds: ${timeInSeconds}" >> ~/summary.log
fi

#
# If we made it here, everything worked.
#
UpdateTestState $ICA_TESTCOMPLETED

exit 0

