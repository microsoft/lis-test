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

########################################################################
#
# provisionUtilVMForLisa.sh
#
# Description:
#    Util VM is a Non-SUT VM, which acts as many roles, such as iSCSI
#    server, NFS server, and one of nodes in "internal" network.
#    Provisioning Util VM has the same steps as provisioning Linux, but
#    adds following steps:
#        install and setup NFS server
#        install and setup iSCSI server
#
########################################################################


ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}


UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

#######################################################################
#
# LinuxRelease()
#
#######################################################################
LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux\|Oracle" /etc/{issue,*release,*version}`

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        *CentOS*6.*)
            echo "CENTOS6";;
        *CentOS*7*)
            echo "CENTOS7";;
        *SUSE*)
            echo "SLES";;
        *Red*6.*)
            echo "RHEL6";;
        *Red*7*)
            echo "RHEL7";;
        Debian*)
            echo "DEBIAN";;
		Oracle*)
		    echo "ORACLE";;
    esac
}

#######################################################################
#
# Static IP address setting
#
#######################################################################
SetIPAddr()
{
    LogMsg "Info: Set IPv4 address $VMIPADDR and IPv6 address $VMIPV6ADDR"
    ip link show "$InternalIfName" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "Error: no interface $InternalIfName found."
		return 1
	fi
    LogMsg "Info: Set $InternalIfName IPv4 address to $VMIPADDR, mask $VMNETMASK"
    CreateIfupConfigFile "$InternalIfName" "static" "$VMIPADDR" "$VMNETMASK"

    LogMsg "Info: Set $InternalIfName IPv6 address to $VMIPV6ADDR"
    ifcfg_file_path="/etc/sysconfig/network-scripts/ifcfg-$InternalIfName"
    cat <<-EOF >> "$ifcfg_file_path"
        IPV6ADDR="$VMIPV6ADDR"
        IPV6INIT=yes
EOF
    ifdown $InternalIfName
    ifup $InternalIfName
}

#######################################################################
#
# Setup NFS
#
#######################################################################
SetNFS()
{
    LogMsg "Info: Installing NFS rpm packages"
    if ! rpm -qa | grep -qw nfs; then
        yum -y install nfs*
    fi

    mkdir -p /nfs_share
    # no_root_squash is for client mounting with root.
    echo "/nfs_share    *(rw,nohide,no_root_squash,sync)" > /etc/exports

    if [ $1 -eq 7 ]; then
        # Restart rpcbind first!
        systemctl restart rpcbind
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to restart rpcbind service"
        fi
        systemctl restart nfs-server
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to restart nfs service"
        fi
        systemctl enable rpcbind
        systemctl enable nfs-server
    fi
    if [ $1 -eq 6 ]; then
        service rpcbind restart
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to restart rpcbind service"
        fi
        service nfs restart
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to restart nfs service"
        fi
        chkconfig nfs on
        chkconfig rpcbind on
    fi
    if [ $? -ne 0 ]; then
	    LogMsg "Error: Unable to set nfs boot start"
	fi
}

#######################################################################
#
# Setup iSCSI
#
#######################################################################
SetiSCSI()
{
    #
    # Create the new partition
    #
    (echo n; echo p; echo 1; echo ; echo ;echo w) | fdisk /dev/sdb 2> /dev/null
    if [ $? -gt 0 ]; then
        LogMsg "Error: Failed to create partition"
    fi
    LogMsg "Info: Partition created"

    if [ $1 -eq 7 ]; then
        LogMsg "Info: Installing targetcli rpm packages"
        if ! rpm -qa | grep -qw targetcli; then
            yum -y install targetcli
        fi

        LogMsg "Info: configure saveconfig.json file"
        cat <<-EOF > "/etc/target/saveconfig.json"
        {
          "fabric_modules": [],
          "storage_objects": [
            {
              "attributes": {
                "block_size": 4096,
                "emulate_3pc": 1,
                "emulate_caw": 1,
                "emulate_dpo": 0,
                "emulate_fua_read": 0,
                "emulate_fua_write": 1,
                "emulate_model_alias": 1,
                "emulate_rest_reord": 0,
                "emulate_tas": 1,
                "emulate_tpu": 0,
                "emulate_tpws": 0,
                "emulate_ua_intlck_ctrl": 0,
                "emulate_write_cache": 0,
                "enforce_pr_isids": 1,
                "force_pr_aptpl": 0,
                "is_nonrot": 0,
                "max_unmap_block_desc_count": 1,
                "max_unmap_lba_count": 67108856,
                "max_write_same_len": 65535,
                "optimal_sectors": 1024,
                "pi_prot_format": 0,
                "pi_prot_type": 0,
                "queue_depth": 128,
                "unmap_granularity": 4096,
                "unmap_granularity_alignment": 0
              },
              "dev": "/dev/sdb1",
              "name": "scsi_disk1_server",
              "plugin": "block",
              "readonly": false,
              "write_back": false,
              "wwn": "d2341df7-0f2c-461f-87ec-1ac6c2d7faa6"
            }
          ],
          "targets": [
            {
              "fabric": "iscsi",
              "tpgs": [
                {
                  "attributes": {
                    "authentication": 0,
                    "cache_dynamic_acls": 1,
                    "default_cmdsn_depth": 64,
                    "default_erl": 0,
                    "demo_mode_discovery": 1,
                    "demo_mode_write_protect": 0,
                    "generate_node_acls": 1,
                    "login_timeout": 15,
                    "netif_timeout": 2,
                    "prod_mode_write_protect": 0,
                    "t10_pi": 0
                  },
                  "enable": true,
                  "luns": [
                    {
                      "index": 0,
                      "storage_object": "/backstores/block/scsi_disk1_server"
                    }
                  ],
                  "node_acls": [],
                  "parameters": {
                    "AuthMethod": "CHAP,None",
                    "DataDigest": "CRC32C,None",
                    "DataPDUInOrder": "Yes",
                    "DataSequenceInOrder": "Yes",
                    "DefaultTime2Retain": "20",
                    "DefaultTime2Wait": "2",
                    "ErrorRecoveryLevel": "0",
                    "FirstBurstLength": "65536",
                    "HeaderDigest": "CRC32C,None",
                    "IFMarkInt": "2048~65535",
                    "IFMarker": "No",
                    "ImmediateData": "Yes",
                    "InitialR2T": "Yes",
                    "MaxBurstLength": "262144",
                    "MaxConnections": "1",
                    "MaxOutstandingR2T": "1",
                    "MaxRecvDataSegmentLength": "8192",
                    "MaxXmitDataSegmentLength": "262144",
                    "OFMarkInt": "2048~65535",
                    "OFMarker": "No",
                    "TargetAlias": "LIO Target"
                  },
                  "portals": [
                    {
                      "ip_address": "0.0.0.0",
                      "iser": false,
                      "port": 3260
                    }
                  ],
                  "tag": 1
                }
              ],
              "wwn": "iqn.2016-05.com.example.server:target2"
            }
          ]
        }
EOF
        systemctl restart target
        systemctl enable target
    fi
    if [ $1 -eq 6 ]; then
        LogMsg "Info: Installing scsi-target-utils rpm packages"
        if ! rpm -qa | grep -qw scsi-target-utils; then
            yum -y install scsi-target-utils
        fi

        LogMsg "Info: configure targets.conf file"
        cat <<-EOF > "/etc/tgt/targets.conf"
            default-driver iscsi
            <target iqn.2016-05.com.example.server:target1>
                backing-store /dev/sdb1
                write-cache off
            </target>
EOF
        service tgtd restart
        if [ $? -ne 0 ]; then
    	    LogMsg "Error: Unable to restart tgtd service"
    	fi
        chkconfig tgtd on
        if [ $? -ne 0 ]; then
    	    LogMsg "Error: Unable to set tgtd boot start"
    	fi
    fi
}

#######################################################################
#
# Provision RHEL
#
#######################################################################
RhelTasks()
{
    LogMsg "Info : Rhel Tasks"
	#
	# Disable the firewall
	#
	LogMsg "Info : Disabling the firewall"
    if [ $1 -eq 7 ]; then
        systemctl stop firewalld
        systemctl disable firewalld
    fi
    if [ $1 -eq 6 ]; then
        service iptables stop
    	chkconfig iptables off

    	service ip6tables stop
    	chkconfig ip6tables off
    fi

	#
	# Disable SELinux
	#
	LogMsg "Info : Disabling SELinux"
    sed -i '/^SELINUX=/cSELINUX=disabled' /etc/selinux/config

	#
	# Create a list of packages to install, then ensure they are installed
	#
	installError=0
    if [ $1 -eq 7 ]; then
	    packagesToInstall=(at bridge-utils btrfs-progs crash dos2unix dosfstools e2fsprogs e2fsprogs-libs util-linux gpm dump system-config-kdump libaio-devel nano ntp ntpdate parted wget xfsprogs iscsi-initiator-utils bc)
    fi
    if [ $1 -eq 6 ]; then
	    packagesToInstall=(at bridge-utils btrfs-progs crash dos2unix dosfstools e2fsprogs e2fsprogs-libs util-linux gpm dump system-config-kdump libaio-devel nano ntp ntpdate parted wget iscsi-initiator-utils bc)
    fi
	for p in "${packagesToInstall[@]}"
	do
	    LogMsg "Info : Processing package '${p}'"
		rpm -q "${p}" > /dev/null
		if [ $? -ne 0 ]; then
		    LogMsg "Info : Installing package '${p}'"
			yum -y install "${p}"
			if [ $? -ne 0 ]; then
			    LogMsg "Error: failed to install package '${p}'"
				installError=1
			fi
		fi
	done

	#
	# Group Install the Development tools
	#
	LogMsg "Info : groupinstall of 'Development Tools'"
	yum -y groupinstall "Development Tools"
	if [ $? -ne 0 ]; then
	    LogMsg "Error: Unable to groupinstall 'Development Tools'"
		installError=1
	fi

	if [ $installError -eq 1 ]; then
	    LogMsg "Error: Not all packages successfully installed - terminating"
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi

	#
	# reiserfs support is in a separate repository
	#
	LogMsg "Info : Adding the elrepo key"
	rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
	if [ $? -ne 0 ]; then
	    LogMsg "Error: Unable to import key for elrepo"
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi

    if [ $1 -eq 7 ]; then
        LogMsg "Info : Adding the elrepo-7 rpm"
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
    fi
    if [ $1 -eq 6 ]; then
        LogMsg "Info : Adding the elrepo-6 rpm"
	    rpm -Uvh http://www.elrepo.org/elrepo-release-6-6.el6.elrepo.noarch.rpm
    fi
	if [ $? -ne 0 ]; then
	    LogMsg "Error: Unable to install elrepo rpm"
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi

	LogMsg "Info : Installing the reiserfs-utils from the elrepo repository"
	yum -y install reiserfs-utils
	if [ $? -ne 0 ]; then
	    LogMsg "Error: Unable to install the reiserfs-utils"
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi

    SetIPAddr
    SetNFS $1
    SetiSCSI $1
}

#######################################################################
#
# Main script body
#
#######################################################################

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

#
# Cleanup any summary log files left behind by a separate test case
#
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Source the constants file
#
if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file!"
    UpdateSummary "ERROR: Unable to source the constants file!"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#
# Display contents of constants.sh so it is captured in the log file
#
cat ~/${CONSTANTS_FILE}

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    LogMsg "Error: unable to source utils.sh!"
    UpdateTestState $ICA_TESTABORTED
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

#
#
# Determine the Linux distro, and perform distro specific tasks
#
distro=`LinuxRelease`
case $distro in
    "CENTOS6" | "RHEL6")
	    RhelTasks 6
	;;
    "CENTOS7" | "RHEL7")
	    RhelTasks 7
	;;
	*)
	    msg="Error: Distro '${distro}' not supported"
		LogMsg "${msg}"
		UpdateTestState $ICA_TESTFAILED
		exit 1
	;;
esac

#
# Provision the SSH keys
#   Note: This is now performed in the setup script.
#LogMsg "Info : Provisioning SSH keys"
#ProvisionSshKeys

UpdateTestState $ICA_TESTCOMPLETED

exit 0
