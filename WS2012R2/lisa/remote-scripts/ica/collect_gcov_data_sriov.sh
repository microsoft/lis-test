#!/bin/bash

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

UpdateTestState() {
    echo $1 > ~/state.txt
}

#declare -a drivers_loc=( 'drivers/hv/channel.c'
#                         # af_hvsock.c - not found on upstream
#                         'drivers/hv/channel_mgmt.c'
#                         'drivers/hv/connection.c'
#                         'drivers/hid/hid-core.c'
#                         'drivers/hid/hid-debug.c'
#                         'drivers/hid/hid-hyperv.c'
#                         'drivers/hid/hid-input.c'
#                         'drivers/hid/hv.c'
#                         #'drivers/hv/hv_balloon.c' - not instrumented
#                         #'drivers/hv/hv_compat.c' - not instrumented
#                         'drivers/hv/hv_fcopy.c'
#                         'drivers/hv/hv_kvp.c'
#                         'drivers/hv/hv_snapshot.c'
#                         'drivers/hv/hv_util.c'
#                         'drivers/hv/hv_utils_transport.c'
#                         # hvnd_addr.c - not found on upstream
#                         'drivers/input/serio/hyperv-keyboard.c'
#                         'drivers/video/fbdev/hyperv_fb.c'
#                         'drivers/net/hyperv/netvsc.c'
#                         'drivers/net/hyperv/netvsc_drv.c'
#                         # 'drivers/infiniband/hw/cxgb4/provider.c' - not instrumented
#                         'drivers/hv/ring_buffer.c'
#                         'drivers/net/hyperv/rndis_filter.c'
#                         'drivers/scsi/storvsc_drv.c'
#                         # vmbus_rdma.c - not found on upstream )
#                         'drivers/hv/vmbus_drv.c' )

declare -a mlx_drivers_loc=( 'drivers/net/ethernet/mellanox/mlx4/alloc.c'
                            'drivers/net/ethernet/mellanox/mlx4/catas.c'
                            'drivers/net/ethernet/mellanox/mlx4/cmd.c'
                            'drivers/net/ethernet/mellanox/mlx4/cq.c'
                            'drivers/net/ethernet/mellanox/mlx4/eq.c'
                            'drivers/net/ethernet/mellanox/mlx4/fw.c'
                            'drivers/net/ethernet/mellanox/mlx4/fw_qos.c'
                            'drivers/net/ethernet/mellanox/mlx4/icm.c'
                            'drivers/net/ethernet/mellanox/mlx4/intf.c'
                            'drivers/net/ethernet/mellanox/mlx4/main.c'
                            'drivers/net/ethernet/mellanox/mlx4/mcg.c'
                            'drivers/net/ethernet/mellanox/mlx4/mr.c'
                            'drivers/net/ethernet/mellanox/mlx4/pd.c'
                            'drivers/net/ethernet/mellanox/mlx4/port.c'
                            'drivers/net/ethernet/mellanox/mlx4/profile.c'
                            'drivers/net/ethernet/mellanox/mlx4/qp.c'
                            'drivers/net/ethernet/mellanox/mlx4/reset.c'
                            'drivers/net/ethernet/mellanox/mlx4/sense.c'
                            'drivers/net/ethernet/mellanox/mlx4/srq.c'
                            'drivers/net/ethernet/mellanox/mlx4/resource_tracker.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_main.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_tx.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_rx.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_ethtool.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_port.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_cq.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_resources.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_netdev.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_selftest.c'
                            'drivers/net/ethernet/mellanox/mlx4/en_clock.c' )

declare -a lib_files=( 'hyperv.h' 'mshyperv.h' 'sync_bitops.h'
                       'access_ok.h' 'be_byteshift.h' 'be_memmove.h'
                       'be_struct.h' 'generic.h' 'le_byteshift.h' 'le_memmove.h'
                       'le_struct.h' 'memmove.h' 'packed_struct.h'
                       'af_hvsock.h' 'atomic.h' 'export.h' 'hid-debug.h' 'hid.h'
                       'hidraw.h' 'hv_compat.h' 'rndis.h' 'hid-uuid.h'
                       'hid.h' 'ktime.h' 'bitops.h' 'seqlock.h' 'math64.h' 'clocksource.h'
                       'timekeeping.h' 'timecounter.h' 'time.h' 'device.h' 'compiler.h'
                       'processor.h' )

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
    for driver in "${mlx_drivers_loc[@]}"
    do
        if [ -f $(basename "${driver}").gcov ]; then
            ln $(basename "${driver}").gcov $(basename "${driver}")_${index}.gcov
            zip ~/gcov_data.zip $(basename "${driver}")_${index}.gcov
        fi
    done
#    for lib in "${lib_files[@]}"
#    do
#        if [ -f $(basename "${lib}").gcov ]; then
#            ln $(basename "${lib}").gcov $(basename "${lib}")_${index}.gcov
#            zip ~/gcov_data.zip $(basename "${lib}")_${index}.gcov
#        fi
#    done
#    for daemon in "${daemons_loc[@]}"
#    do
#        if [ -f $(basename "${daemon}").gcov ]; then
#            ln $(basename "${daemon}").gcov $(basename "${daemon}")_${index}.gcov
#            zip ~/gcov_data.zip $(basename "${daemon}")_${index}.gcov
#        fi
#    done
}

rm -f ~/gcov_data.zip
#DumpGcovDaemon "${daemons[@]}"
#cd ${DAEMON_GCOV_LOC}
i=1
#for daemon in "${daemons_loc[@]}"
#do
#    rm -rf *.gcov
#    gcov ${SOURCE_LOC}${daemon} -o ${DAEMON_GCOV_LOC}
#    ZipAllGcov "${i}"
#    i=$(($i+1))
#done

cd ${SOURCE_LOC}
for driver in "${mlx_drivers_loc[@]}"
do
    rm -rf *.gcov
    gcov ${SOURCE_LOC}${driver} -o ${DRIVER_GCOV_LOC}$(dirname "${driver}")
    ZipAllGcov "${i}"
    i=$(($i+1))
done

cd ~
echo "TestCompleted" > state.txt
#gcovr -g -k -r . --html --html-details -o /tmp/kvp_normal.html
