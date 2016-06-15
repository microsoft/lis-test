#!/bin/bash
# auto_rdos_Reboot.sh
# e.g. auto_rdos_Reboot.sh reboot_count
#

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during running of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

rm -f ~/summary.log
touch ~/summary.log
echo "Covers: auto RDOS reboot stress tests" >> ~/summary.log

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# waiting for lisa to read state.txt
sleep 10

#
# Source the constants.sh file to pickup definitions from
# the ICA automation
#
if [ -e ./$CONSTANTS_FILE ]; then
    LogMsg "CONSTANTS FILE: $(cat $CONSTANTS_FILE)"
    source ./$CONSTANTS_FILE
else
    LogMsg "Warn : no ${CONSTANTS_FILE} found"
fi

#
# init $boot_count and write it to /root/count.txt
#
if [[ -z $REBOOT_COUNT ]]
then
    LogMsg "no reboot count entered. set reboot count to 3"
    reboot_count=3
else
    LogMsg "reboot count set to $REBOOT_COUNT"
    reboot_count=$REBOOT_COUNT
fi

echo "INFO: this test reboot VM $reboot_count times" >> ~/summary.log
echo $reboot_count > /root/count.txt

# clean up log file
echo -n "" > /root/AUTO_Reboot.log

#
# deploy reboot script to directory /root
#

reboot_script=AUTO_Reboot.sh

if  ! [[ -f /root/$reboot_script ]]; then
    echo "ERROR: reboot script:$reboot_script not exist" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
	exit 1
else
	dos2unix /root/$reboot_script
	chmod +x /root/$reboot_script
fi

#
# edit root/rc.local and root/rc.d/rc.local to
# make sure automate run script during boot
#

reboot_script_path="/root/$reboot_script"

#write script path to /etc/rc.d/rc.local
if [[ -f /etc/rc.d/rc.local ]]
then
	sed "/^\s*exit 0/i ${reboot_script_path}" /etc/rc.d/rc.local -i

	if ! grep -q "root/$reboot_script" /etc/rc.d/rc.local
	then
		echo "Add root/$reboot_script to /etc/rc.d/rc.local"
		echo $reboot_script_path >> /etc/rc.d/rc.local
	fi
fi

#if distro is SUSE then configure /etc/rc.d/after.local
if [[ -f /etc/SuSE-release ]]
then
	if [[ -f /etc/rc.d/after.local ]]
	then
		echo "INFO: the distro is SUSE. update /etc/rc.d/after.local" >> ~/summary.log
		echo "/root/AUTO_Reboot.sh" >> /etc/rc.d/after.local
		chmod +x /etc/rc.d/after.local
	elif [[ -f /etc/rc.d/boot.local ]]
	then
		echo "INFO: the distro is SUSE. update /etc/rc.d/boot.local" >> ~/summary.log
		echo "/root/AUTO_Reboot.sh" >> /etc/rc.d/boot.local
		chmod +x /etc/rc.d/boot.local
	else
		echo "INFO: boot.local and after.local files are missing in the distro" >> ~/summary.log
	fi
fi

[[ -f /etc/rc.d/rc.local ]] && chmod +x /etc/rc.d/rc.local

init 6
