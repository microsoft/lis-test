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

declare -a drivers_loc=( 'drivers/hv/channel.c'
                         'drivers/hv/channel_mgmt.c'
                         'drivers/hv/connection.c'
                         'drivers/hid/hid-core.c'
                         'drivers/hid/hid-debug.c'
                         'drivers/hid/hid-hyperv.c'
                         'drivers/hid/hid-input.c'
                         'drivers/hid/hv.c'
                         'drivers/hv/hv_balloon.c'
                         'drivers/hv/hv_compat.c'
                         'drivers/hv/hv_fcopy.c'
                         'drivers/hv/hv_kvp.c'
                         'drivers/hv/hv_snapshot.c'
                         'drivers/hv/hv_util.c'
                         'drivers/hv/hv_utils_transport.c'
                         'drivers/input/serio/hyperv-keyboard.c'
                         'drivers/video/fbdev/hyperv_fb.c'
                         'drivers/net/hyperv/netvsc.c'
                         'drivers/net/hyperv/netvsc_drv.c'
                         'drivers/hv/ring_buffer.c'
                         'drivers/net/hyperv/rndis_filter.c'
                         'drivers/scsi/storvsc_drv.c'
                         'drivers/hv/vmbus_drv.c' )

declare -a lib_files=( 'hyperv.h' 'mshyperv.h' 'hv_compat.h' )

SOURCE_LOC="$1"
DRIVER_GCOV_LOC="/sys/kernel/debug/gcov/${SOURCE_LOC}"/
DAEMON_GCOV_LOC="${SOURCE_LOC}/tools/hv/"

declare -a daemons=( 'hv_kvp_daemon' 'hv_vss_daemon' 'hv_fcopy_daemon' )
declare -a daemons_loc=( 'tools/hv/hv_kvp_daemon.c'
                         'tools/hv/hv_fcopy_daemon.c'
                         'tools/hv/hv_vss_daemon.c' )

# Function to get dump gcov data for daemon processes
DumpGcovDaemon()
{
    if [ -z "$1" ]
      then
        echo "Error: please specify the daemon process/es name"
        exit
    fi

    echo "set pagination off" > ~/.gdbinit
    for process in "$@"
    do
        pid=`pidof ${process}`
        if [ -z "$pid" ]
        then
            echo "Error: could not find process: $process"
            continue
        fi
        gcov_tmp_file=/root/gcov_tmp_${pid}
        gcov_log_file=/root/gcov_log_${pid}
        echo "call __gcov_flush()" > ${gcov_tmp_file}
        echo "thread apply all call __gcov_flush()" >> ${gcov_tmp_file}
        gdb -p ${pid} -batch -x ${gcov_tmp_file} --args ${process} > ${gcov_log_file} 2>&1
        rm -f ${gcov_tmp_file}
        if [ -f ${gcov_log_file} ]; then
            rm -f ${gcov_log_file}
        fi
    done
    rm -f ~/.gdbinit
}

# Function to zip all gcov data files generated
ZipAllGcov()
{
    index=$1
    for driver in "${drivers_loc[@]}"
    do
        if [ -f $(basename "${driver}").gcov ]; then
            ln $(basename "${driver}").gcov $(basename "${driver}")_${index}.gcov
            zip ~/gcov_data.zip $(basename "${driver}")_${index}.gcov
        fi
    done
    for lib in "${lib_files[@]}"
    do
        if [ -f $(basename "${lib}").gcov ]; then
            ln $(basename "${lib}").gcov $(basename "${lib}")_${index}.gcov
            zip ~/gcov_data.zip $(basename "${lib}")_${index}.gcov
        fi
    done
    for daemon in "${daemons_loc[@]}"
    do
        if [ -f $(basename "${daemon}").gcov ]; then
            ln $(basename "${daemon}").gcov $(basename "${daemon}")_${index}.gcov
            zip ~/gcov_data.zip $(basename "${daemon}")_${index}.gcov
        fi
    done
}

rm -f ~/gcov_data.zip
DumpGcovDaemon "${daemons[@]}"
cd ${DAEMON_GCOV_LOC}
i=1
for daemon in "${daemons_loc[@]}"
do
    rm -rf *.gcov
    gcov ${SOURCE_LOC}/${daemon} -o ${DAEMON_GCOV_LOC} 2> /dev/null
    ZipAllGcov "${i}"
    i=$(($i+1))
done

cd ${SOURCE_LOC}
for driver in "${drivers_loc[@]}"
do
    rm -rf *.gcov
    gcov ${SOURCE_LOC}/${driver} -o ${DRIVER_GCOV_LOC}$(dirname "${driver}") 2> /dev/null
    ZipAllGcov "${i}"
    i=$(($i+1))
done

cd ~
echo "TestCompleted" > state.txt

# How to generate gcov report
#gcovr -g -k -r . --html --html-details -o /tmp/report.html
