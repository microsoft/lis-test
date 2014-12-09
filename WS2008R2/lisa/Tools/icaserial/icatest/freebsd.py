#!/usr/bin/env python
# -*- coding: UTF-8 -*-

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

######################################################################
#
# Description
#     This is the implementation of all FreeBSD-specific utility
#     functions.
#
# History
#     10/27/2011 Thu     Created by     fuzhouch
#     11/09/2011 Tue     Modified by    xiliang
#
######################################################################
import os
import re
import sys
import time
import subprocess
from icatest.errors import *

# XXX As per information from Internet, it looks like FreeBSD may change
# device name between different versions. Need double confirming.
DEFAULT_SERIAL_PORT_DEVICE = "/dev/cuau1"
__IFCONFIG_EXECUTABLE = "/sbin/ifconfig"

def disable_tty_echo_mode(serial_port_device):
    """
    disable_tty_echo_mode(serial_port_device) -> stty exit code

    Disable echo mode for TTY.
    """
    # By default the serial port device is enabled with echo, so a
    # Windows client may get original request string before getting
    # real result. Disabling echo will result in a simpler design
    # of Windows side.
    config_device = "%s.init" % serial_port_device
    cmdline = [ "/bin/stty", "-f", config_device, "-echo" ]
    stty = subprocess.Popen(cmdline,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return stty.wait()

def set_datetime(hour, minute, month, day, year):
    """
    set_datetime(hour, minute, month, day, year) -> `date' exit code, message
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
    newval = "%04d%02d%02d%02d%02d" % (year, month, day, hour, minute)
    cmdline = ["/bin/date", newval]
    date = subprocess.Popen(cmdline,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    return_code = date.wait()
    output = date.stdout.read().decode('utf-8')
    error = date.stderr.read().decode('utf-8')
    # FIXME This is strictly for FreeBSD 8.2. In my environment date
    # command always returns 2, which means the local time is correctly
    # set but the value can't take effect 'globally'. I'm not sure the
    # scematics of this terminology so I leave it for further
    # investigation. See FreeBSD manpage for more details.
    if return_code == 2:
        return_code = ERROR_SUCCESS
    return return_code, output.split("\n")[0]

def shutdown_system(reboot = False):
    """
    shutdown_system(reboot = False) -> `shutdown' exit code, message
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

        devname: device name: de0, de1, etc...
        addr_type: string. must be ipv4, ipv6, mac or link.

    Returns a tuple, (error_code, address_string). If success,
    error_code is set to ERROR_SUCCESS (0), and the address_string is
    set to the IP address, or a comma-delimitered IP address list,if an
    adapter has multiple addresses assigned to it.

    If anything wrong is found, the return_code is positive integer,
    and address_string is error message.
    """
	# Right now I haven't found a direct command to allow me directly
    # get IPv4 address of specific MAC address. So I have to enumerate
    # each network interfaces and get their MAC addresses until we found
    # what we need.
    #
    if not os.access(__IFCONFIG_EXECUTABLE, os.F_OK):
        return ERROR_FILE_NOT_FOUND, "Tool not found: %s" % __IFCONFIG_EXECUTABLE
		
    addr_type_lower = addr_type.lower()
    if addr_type_lower == "ipv4":
        pattern = re.compile(r"inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
    elif addr_type_lower == "ipv6":
        pattern = re.compile(r"inet6 [0-9a-fA-F]+:[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F]+")
    elif addr_type_lower == "mac" or addr_type_lower == "link":
        pattern = re.compile(r"ether [0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]")
    else:
        return ERROR_BAD_ARGUMENTS, "Bad address type: %s" % addr_type

    cmdline = [__IFCONFIG_EXECUTABLE, devname]
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
        addr_type: string. must be ipv4, ipv6, mac.

    Returns a tuple, (error_code, address_string). If success,
    error_code is set to ERROR_SUCCESS (0), and the address_string is
    set to the IP address, or a comma-delimitered IP address list,if an
    adapter has multiple addresses assigned to it.

    If anything wrong is found, the return_code is positive integer,
    and address_string is error message.
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
    if not os.access(__IFCONFIG_EXECUTABLE, os.F_OK):
        return ERROR_FILE_NOT_FOUND, "Tool not found: %s" % __IFCONFIG_EXECUTABLE
    cmdline = [__IFCONFIG_EXECUTABLE]
    link_proc = subprocess.Popen(cmdline, \
                                 stdout = subprocess.PIPE, \
                                 stderr = subprocess.PIPE)
    link_proc.wait()
    if link_proc.returncode != 0:
        return ERROR_BAD_COMMAND, "Failed to execute child process, return code = %d" % link_proc.returncode

    link_stdout_output = link_proc.stdout.read()

    pattern = re.compile(r"[a-zA-Z][a-zA-Z][0-9]*:")
    results = pattern.findall(link_stdout_output)
	
    for each_if in results:
        if_value = each_if.strip().split(':')[0]
        addr = get_addr_by_device(if_value, "mac")
        if addr[0] == ERROR_SUCCESS:
            if addr[1].lower() == formalized_macaddr.lower():
                ip_addr = get_addr_by_device(if_value, addr_type)
                break
            else:
                # Contiune to find the matched mac address
                continue
        else:
            # Something wrong when querying MAC address list
			continue
    return ip_addr
