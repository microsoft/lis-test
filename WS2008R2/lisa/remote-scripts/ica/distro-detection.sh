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

# Detect the current linux distribution. This is the same distro detection code
# was written for the MAP project.

# Known distribution ID's returned by 'lsb_release':

ID_REDHAT="RedHatEnterpriseServer"     # Red Hat Enterprise Linux 5
ID_ORACLE="EnterpriseEnterpriseServer" # Oracle Enterprise Linux 5
ID_CENTOS="CentOS"                     # CentOS 5
ID_SUSE="SUSE LINUX"                   # SUSE Enterprise Linux 11
ID_FEDORA="Fedora"                     # Fedora 11
ID_UBUNTU="Ubuntu"                     # Ubuntu 9.04
ID_REDHAT6="Red Hat Enterprise Linux Server" # Red Hat Enterprise Linux 6

# Classify the distribution based on package management or other features.
# This is done so the script can make decisions based on the type of distro.
# If something in the script is specific to one distro (i.e. Oracle Enterprise
# Linux) just use the distribution ID (e.g. $ID_ORACLE) for logic decisions.
# If something applies to multiple distributions it may be easier to make logic
# decisions based on the distribution type (e.g. RPM vs DEBIAN) using
# $DESTRIB_CLASS.
#
# Currently the script only supports rpm and debian-base systems).  Currently
# supported values for DISTRIB_CLASS are:
# 	"RPM"
#	"DEBIAN"
#	"UNSUPPORTED"
# Initially set to UNSUPPORTED.  This will be changed later during OS detection
DISTRIB_CLASS="UNSUPPORTED"

DISTRIB_ID="Unknown"
DISTRIB_RELEASE="Unknown"
DISTRIB_DESCRIPTION="Unknown"
DISTRIB_CODENAME="Unknown"

# First, use 'lsb_release' from the Linux Standards Base (LSB) spec to
# determine what distribution this is. Other options for getting the
# distribution release/name are shown below:
# 	- 'lsb_release' command, /etc/lsb-release
#	- /etc/issue
#	- distribution specific files (/etc/redhat-release, etc)

if [ "$(which lsb_release 2> /dev/null)" != "" ]; then
	DISTRIB_ID="$(lsb_release -si)"
	DISTRIB_DESCRIPTION="$(lsb_release -sd)"
	DISTRIB_RELEASE="$(lsb_release -sr)"
	DISTRIB_CODENAME="$(lsb_release -sc)"
else
	# Manually identify other distros if the 'lsb_release' command does not
	# exist.  Manual detection would go something like this...
	# Auto populate release values if /etc/lsb-release exists
	if [ -e /etc/lsb-release ]; then
		. /etc/lsb-release
	# Populate DISTRIB variables with info from /etc/redhat-release
	# Fedora should be picked up here since /etc/redhat-release symlinks
	# to /etc/fedora-release (at least it does on Fedora 12)
	elif [ -e /etc/redhat-release ]; then
		distro_info=$(cat /etc/redhat-release)
		regex="^(.*) release (.*) \((.*)\).*$"
		if [[ "$distro_info" =~ $regex ]]; then
			DISTRIB_ID="${BASH_REMATCH[1]}"
			DISTRIB_RELEASE="${BASH_REMATCH[2]}"
			DISTRIB_CODENAME="${BASH_REMATCH[3]}"
		fi
	#elif [ -e /etc/issue ]; then
	#	# Populate DISTRIB variables with info from /etc/issue
	#       # .../etc/issue would be one of the last resorts
	fi
fi

# Output the distribution detection results
echo "Distribution: $DISTRIB_ID"
echo "Distribution Release: $DISTRIB_RELEASE"
echo "Distribution Description: $DISTRIB_DESCRIPTION"
echo "Distribution Codename: $DISTRIB_CODENAME"

# Classify the distribution
case "$DISTRIB_ID" in
	"$ID_REDHAT" | "$ID_ORACLE" | "$ID_CENTOS" | "$ID_FEDORA" | "$ID_SUSE" | "$ID_REDHAT6")
		DISTRIB_CLASS="RPM" ;;
	"$ID_UBUNTU" )
		DISTRIB_CLASS="DEBIAN" ;;
esac
