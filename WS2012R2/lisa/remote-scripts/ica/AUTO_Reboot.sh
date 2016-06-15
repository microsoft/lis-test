#!/bin/bash
#AUTO_Reboot.sh
#e.g. AUTO_Reboot.sh reboot_count
#

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during running of test

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

reboot_count=`cat /root/count.txt`

#reboot $reboot_count times
if [ $reboot_count -gt 0 ]
then
    reboot_count=`expr $reboot_count - 1`
    echo $reboot_count > /root/count.txt

    #output log to AUTO_Reboot.log
    echo "Reboot No. $reboot_count" >> ~/AUTO_Reboot.log
    echo "Rebooting Now..." >> ~/AUTO_Reboot.log
    date >> ~/AUTO_Reboot.log

    #output log to serial log
    echo "Reboot No. $reboot_count" > /dev/kmsg
    date > /dev/kmsg

    init 6

else
    #recover rc.local file when finish test
    for rc in /etc/rc.local /etc/rc.d/rc.local /etc/rc.d/after.local
    do
        if [[ -f $rc ]]; then
            echo Removing auto reboot in $rc
            sed "/root\/AUTO_Reboot.sh/d" $rc -i
        fi
    done
    
    #test completed report state to lisa
    echo "test completed successfully..." >> ~/summary.log
    UpdateTestState $ICA_TESTCOMPLETED
fi

