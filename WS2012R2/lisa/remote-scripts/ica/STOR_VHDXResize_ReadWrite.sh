LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}


#
# Read/Write mount point
#

mkdir /mnt/ICA/ 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to create directory /mnt/ICA/"
    echo "Creating /mnt/ICA/ directory: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

echo 'testing' > /mnt/ICA/ICA_Test.txt 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to create file /mnt/ICA/ICA_Test.txt"
    echo "Creating file /mnt/ICA/ICA_Test.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

ls /mnt/ICA/ICA_Test.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to list file /mnt/ICA/ICA_Test.txt"
    echo "Listing file /mnt/ICA/ICA_Test.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

cat /mnt/ICA/ICA_Test.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to read file /mnt/ICA/ICA_Test.txt"
    echo "Listing read /mnt/ICA/ICA_Test.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

# unalias rm 2> /dev/null
rm /mnt/ICA/ICA_Test.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to delete file /mnt/ICA/ICA_Test.txt"
    echo "Deleting /mnt/ICA/ICA_Test.txt file: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

rmdir /mnt/ICA/ 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to delete directory /mnt/ICA/"
    echo "Deleting /mnt/ICA/ directory: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi