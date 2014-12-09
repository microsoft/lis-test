#!/usr/bin/env python

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

#####################################################################
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
#####################################################################
#
# Description
#     This is the implementation of all Linux-specific utility functions.
#
######################################################################

import os
import re
import sys
import time
import subprocess
from icatest.errors import *

DEFAULT_SERIAL_PORT_DEVICE = "/dev/ttyS1"
__IP_EXECUTABLE = "/sbin/ip"

def disable_tty_echo_mode(serial_port_device):
    """
    disable_tty_echo_mode(serial_port_device) -> stty exit code

    Disable echo mode for TTY.
    """
    # By default the serial port device is enabled with echo, so a
    # Windows client may get original request string before getting real
    # result. Disabling echo will result in a simpler design of Windows
    # side.
    cmdline = [ "/bin/stty", "-F", serial_port_device, "-echo" ]
    stty = subprocess.Popen(cmdline,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return stty.wait()

def set_datetime(hour, minute, month, day, year):
    """
    set_datetime(hour, minute, month, day, year) -> `date' exit code
    Set system date and time to a new value.
        hour:   00..23
        minute: 00..59
        month:  01..12
        day:    01..31
        year:   four digit year number
    """
    if type(hour) is not type(0) or hour < 0 or hour > 23:
        return ERROR_INVALID_PARAMETER
    if type(minute) is not type(0) or minute < 0 or minute > 59:
        return ERROR_INVALID_PARAMETER
    if type(month) is not type(0) or month < 1 or month > 12:
        return ERROR_INVALID_PARAMETER
    if type(day) is not type(0) or day < 1 or day > 31:
        return ERROR_INVALID_PARAMETER
    if type(year) is not type(0) or year < 1 or year > 9999:
        return ERROR_INVALID_PARAMETER
    newval = "%02d%02d%02d%02d%04d" % (month, day, hour, minute, year)
    cmdline = ["/bin/date", newval]
    date = subprocess.Popen(cmdline,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    return_code = date.wait()
    output = date.stdout.read().decode('utf-8')
    error = date.stderr.read().decode('utf-8')
    return return_code, output.split("\n")[0]

def shutdown_system(reboot = False):
    """
    shutdown_system(reboot = False) -> return_code, message
    Trigger a shutdown action. Caller can set reboot = True if a reboot
    operation is needed, or system will poweroff.

    Note that all shutdown operations triggered by shutdown_system()
    will actually happen after 10 seconds. This is to make sure
    icadaemon can return exit code correctly.
    """
    time.sleep(10)
    if reboot:
        cmdline = ["/usr/bin/env", 'reboot']
    else:
        cmdline = ["/usr/bin/env", 'halt', '-p']
    shutdown = subprocess.Popen(cmdline,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    return_code = shutdown.wait()
    output = shutdown.stdout.read().decode('utf-8')
    error = shutdown.stderr.read().decode('utf-8')
    return return_code, output.split("\n")[0]

def get_addr_by_device(devname, addr_type):
    """
    get_ip_by_device(devname, addr_type) -> address string or None
    Get IP address by device name.

        devname: device name: eth0, eth1, etc...
        addr_type: string. must be ipv4, ipv6, mac or link.

    Returns a tuple, (error_code, address_string). If success,
    error_code is set to ERROR_SUCCESS (0), and the address_string is
    set to the IP address, or a comma-delimitered IP address list,if an
    adapter has multiple addresses assigned to it.

    If anything wrong is found, the return_code is positive integer,
    and address_string is error message.
    """
    if not os.access(__IP_EXECUTABLE, os.F_OK):
        return ERROR_FILE_NOT_FOUND, "Tool not found: %s" % __IP_EXECUTABLE

    cmdline = [__IP_EXECUTABLE, "", "addr", "show", "dev", ""]
    addr_type_lower = addr_type.lower()
    if addr_type_lower == "ipv4":
        cmdline[1] = "-4"
        cmdline[5] = devname
        pattern = re.compile(r"inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
    elif addr_type_lower == "ipv6":
        cmdline[1] = "-6"
        cmdline[5] = devname
        pattern = re.compile(r"inet6 [0-9a-fA-F]+:[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F]+")
    elif addr_type_lower == "mac" or addr_type_lower == "link":
        cmdline[1] = "-0"
        cmdline[5] = devname
        pattern = re.compile(r"link/ether [0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]")
    else:
        return ERROR_BAD_ARGUMENTS, "Bad address type: %s" % addr_type

    ip_proc = subprocess.Popen(cmdline, \
                               stdout = subprocess.PIPE, \
                               stderr = subprocess.PIPE)
    ip_proc.wait()
    if ip_proc.returncode != 0:
        return ERROR_BAD_COMMAND, "Failed to execute child process, return code = %d" % ip_proc.returncode

    ip_stdout_output = ip_proc.stdout.read()
    # Python 3 will complain if we don't convert ip_stdout_output
    # to string.
    found_results = pattern.findall(str(ip_stdout_output), re.MULTILINE)
    if len(found_results) == 0:
        return ERROR_BAD_FORMAT, "Address not found from /sbin/ip output"
    # The result should be some kinds of ["inet", "<ip address>"].
    # We want only the ip addresses. We also got to make sure we can
    # return a list when a network adapter has multiple IP addresses.
    found_ipaddrs = map(lambda s: s.split(" ")[1], found_results)
    return ERROR_SUCCESS, ",".join(found_ipaddrs)


def get_addr_by_mac_address(macaddr, addr_type):
    """
    get_ip_by_mac_address(macaddr, addr_type) -> address string or None
    Get IP address by device name.

        devname: macaddress name: 1234567890ab or 12:34:56:78:90:ab
        addr_type: string. must be ipv4, ipv6, mac or link.

    Returns a tuple, (error_code, address_string). If success,
    error_code is set to ERROR_SUCCESS (0), If anything wrong is found,
    the return_code is positive integer, and address_string is error
    message.
    """
    formalized_macaddr = None
    if len(macaddr) == 17:
        macaddr_fields = macaddr.split(":")
        if len(macaddr_fields) == 6:
            formalized_macaddr = ":".join(macaddr_fields)
        else:
            return ERROR_BAD_ARGUMENTS, "Invalid MAC address: %s" % macaddr
    elif len(macaddr) == 12:
        formalized_macaddr = "%s:%s:%s:%s:%s:%s" % \
                             (macaddr[0:2], macaddr[2:4], macaddr[4:6],\
                              macaddr[6:8], macaddr[8:10], macaddr[10:12])
    else:
        return ERROR_BAD_ARGUMENTS, "Invalid MAC address: %s" % macaddr

    # Right now I haven't found a direct command to allow me directly
    # get IPv4 address of specific MAC address. So I have to enumerate
    # each network interfaces and get their MAC addresses until we found
    # what we need.
    #
    if not os.access(__IP_EXECUTABLE, os.F_OK):
        return ERROR_FILE_NOT_FOUND, "Tool not found: %s" % __IP_EXECUTABLE
    cmdline = [__IP_EXECUTABLE, "link", "show" ]
    link_proc = subprocess.Popen(cmdline, \
                                 stdout = subprocess.PIPE, \
                                 stderr = subprocess.PIPE)
    link_proc.wait()
    if link_proc.returncode != 0:
        return ERROR_BAD_COMMAND, "Failed to execute child process, return code = %d" % link_proc.returncode

    link_stdout_output = link_proc.stdout.read()

    pattern = re.compile(r"[0-9][0-9]*: [a-zA-Z][a-zA-Z0-9]*: ")
    # Python 3 will complain if we don't convert link_stdout_output
    # to string.
    found_results = pattern.findall(str(link_stdout_output), re.MULTILINE)
    if len(found_results) == 0:
        return ERROR_BAD_FORMAT, "MAC addr not found from /sbin/ip output"
    found_ifaces = map(lambda s: s.split(":")[1].lstrip(), found_results)

    results = (ERROR_FILE_NOT_FOUND, \
               "MAC address not found: %s" % formalized_macaddr)
    for each_iface in found_ifaces:
        link_results = get_addr_by_device(each_iface, "link")
        # NOTE: We always assume a network interface has one and only
        # one MAC address.
        if link_results[0] == ERROR_SUCCESS:
            if link_results[1].upper() == formalized_macaddr.upper():
                # This is the interface we want.
                results = get_addr_by_device(each_iface, addr_type)
                break
        else:
            # Something wrong when querying MAC address list
            results = link_results
            break
    return results
