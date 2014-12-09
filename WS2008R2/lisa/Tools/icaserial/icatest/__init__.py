#!/usr/bin/env python
# -*- coding: utf-8 -*-

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

"""
The icatest module provides all supporting libraries (classes and
functions) used by ICA automation test scripts.
"""
import icatest.daemon
import icatest.errors

import os
import subprocess

# Now we determine platforms
try:
    cmdline = [ "/usr/bin/env", "uname", "-s" ]
    task = subprocess.Popen(cmdline, \
                            stdout = subprocess.PIPE, \
                            stderr = subprocess.PIPE)
    task_return_code = task.wait()
    task_output = task.stdout.read().decode('utf-8')
    task_error  = task.stderr.read().decode('utf-8')
    osname = task_output.split("\n")[0].lower()
except OSError:
    msg = "ERROR: Can't find /usr/bin/env or uname, cannot detect OS"
    code = icatest.errors.ERROR_BAD_ENVIRONMENT
    icatest.daemon.write_log(icatest.daemon.STDERR_FD, code, msg)
    raise ICAException(code, msg)

if osname == "freebsd":
    import icatest.freebsd as platform_lib
elif osname == "linux":
    import icatest.linux as platform_lib
else:
    msg = "Unsupported OS from uname -s: %s" % osname
    code = icatest.errors.ERROR_BAD_ENVIRONMENT
    icatest.daemon.write_log(icatest.daemon.STDERR_FD, None, code, msg)
    raise ICAException(code, msg)
