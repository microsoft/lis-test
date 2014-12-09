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

#######################################################################
#
# Description
#     This is a library that works for all PISIX platforms.
#
# History
#     10/27/2011 Thu    Created by     fuzhouch
#######################################################################

import re
import os
import sys
import atexit
import select
import syslog
import signal
import pickle
import base64
import subprocess
import icatest
from icatest.errors import *

if hasattr(os, "devnull"):
    NULL_TO = os.devnull
else:
    NULL_TO = "/dev/null"
UMASK = 0
WORKDIR = "/"
MAXFD = 1024
# POSIX ensures an atomic read/write operation for 512 bytes. We leave
# one byte for "\n"
MAX_STRLEN = 511

STDIN_FD = 1
STDOUT_FD = 1
STDERR_FD = 2
READ = 0
WRITE = 0

REQUEST = re.compile(r"^ *(get|set|send) +([\w\d]+) +(.*[^ ]) *$", re.I)
REQUEST_NO_DATA = re.compile(r"^ *(get|set|send) +([\w\d]+) *$", re.I)
RESPONSE = re.compile(r"^ *([\w\d]+) (\d+) +(.*)$", re.I)
RESPONSE_NO_DATA = re.compile(r"^ *([\w\d]+) (\d+) *$", re.I)
ESCAPE_TOKEN = re.compile(r"\\(.)")

class ICAException(Exception):
    def __init__(self, error_code, msg):
        Exception.__init__(self)
        self.error_code = error_code
        self.msg = msg

def split_with_escape(s, delimiter, escape = '\\'):
    """
    split_with_escape(s, delimiter, escape = '\\') -> splitted list

    Split given string with given delimiter, ignoring escape tokens.
    The delimiter and escape must be one character. Also, this function
    assume escape token can be used to escape itself.

    Note that split_with_escape() does not remove escape token. This is
    to make sure the caller can do multi-level splitting against a
    string.

    Return splitted list if success, or None if failed.
    """
    if len(delimiter) != 1 or len(escape) != 1:
        return None
    split_index = []
    used_escape_index = []
    for i in range(0, len(s)):
        if s[i] == escape:
            if i - 1 > 0:
                if s[i-1] == escape and i-1 in used_escape_index:
                    # This escape is escaped by previous one
                    # Should be treated as regular character
                    pass
                else:
                    used_escape_index.append(i)
            else:
                used_escape_index.append(i)

    for i in range(0, len(s)):
        if s[i] == delimiter:
            if i - 1 > 0:
                if s[i-1] != escape or i-1 not in used_escape_index:
                    split_index.append(i) # Real delimter, split it
                else:
                    pass # Escaped delimter, treat it as regular character
            else:
                split_index.append(i) # Real delimter, split it
        else:
            continue # Other regular characters, accept it.
    splitted_list = []
    index = 0
    escaped_delimiter = "%c%c" % (escape, delimiter)
    for each_split in split_index:
        split = s[index:each_split].replace(escaped_delimiter, delimiter)
        splitted_list.append(split)
        index = (each_split + 1) # +1 to ignore delimiter
    splitted_list.append(s[index:].replace(escaped_delimiter, delimiter))
    return splitted_list

def parse_params(param_str, case_sensitive = False):
    """
    parse_params(param_str, case_sensitive = False) -> a map of parameters

    Parse parameter from given string. The string follows a format like
    below:
        param1=value1,param2=value2,...

    We support escape token '\\' to escape "," and "=".

    If case_sensitive is set to False, parse_params() makes sure all
    *keys* are in low case.

    """
    ret = {}
    escape = "\\"
    delimiter = ","
    delimiter2 = "="
    keyvalues = split_with_escape(param_str, delimiter, escape)
    if keyvalues is None:
        return None
    # We allow empty elements when splitting "," token. This behavior
    # allows we pass whitespaces in kvp values when there's only one
    # parameter in given command.
    keyvalues = filter(lambda x: len(x) != 0, keyvalues)
    for each_keyvalue in keyvalues:
        key_and_value = split_with_escape(each_keyvalue, delimiter2, escape)
        if key_and_value is None or len(key_and_value) != 2:
            return None
        if case_sensitive:
            key = key_and_value[0]
        else:
            key = key_and_value[0].lower()
        key = ESCAPE_TOKEN.sub("\\1", key)
        ret[key] = ESCAPE_TOKEN.sub("\\1", key_and_value[1])
    return ret

def parse_request(request):
    """
    parse_request(request) -> verb, noun, optional_data

    Parse request string and return verb, noun and optional_data. If
    there's any parse error, the return value will be (None, None,
    None).

    Please note that parse_request removes any trailing whitespaces in a
    request string. This is required by ICA/LiSA framework. As a side
    effect, if a given request has a parameter, which uses whitespaces
    at the end of its value, the accepted value will be changed because
    the whitespaces will be silently removed.
    """
    if type(request) is not type(""):
        return None, None, None

    # NOTE The pattern, REQUEST, will remove trailing whitespaces.
    match = REQUEST.match(request)
    if match is None:
        match = REQUEST_NO_DATA.match(request)
        if match is None:
            return None, None, None
        else:
            return match.group(1), match.group(2), ""
    else:
        return match.group(1), match.group(2), match.group(3)

def parse_response(response):
    """
    parse_response(response) -> noun, return_code, optional_data

    Parse response and return noun return_code and optional_data.
    """
    if type(response) is not type(""):
        return None, None, None
    match = RESPONSE.match(response)
    if match is None:
        match = RESPONSE_NO_DATA.match(response)
        if match is None:
            return None, None, None
        else:
            return match.group(1), match.group(2), ""
    else:
        return match.group(1), match.group(2), match.group(3)



def write_log(fd, cmd, error_code, msg, trunc = False):
    if cmd is None:
        if msg is None or msg == "":
            info = "%d" % error_code
        else:
            info = "%d %s" % (error_code, msg)
    else:
        if msg is None or msg == "":
            info = "%s %d" % (cmd, error_code)
        else:
            info = "%s %d %s" % (cmd, error_code, msg)
    if error_code == ERROR_SUCCESS:
        syslog.syslog(syslog.LOG_INFO, info)
    else:
        syslog.syslog(syslog.LOG_ERR, info)
    if trunc:
        if len(info) > MAX_STRLEN:
            if cmd is None:
                # General message, no need to take care about string
                # format.
                info = info[:MAX_STRLEN]
            else:
                # It should be a resopnse. We must make sure all
                # response has return code.
                if msg is None or msg == "":
                    # Command name is too long
                    error_code_str = "%d" % error_code
                    error_code_len = len(error_code_str)
                    cmd_len = len(cmd)
                    delta = cmd_len + 1 + error_code_len - MAX_STRLEN
                    cmd_truncated = cmd[:cmd_len - delta]
                    info = "%s %d" % (cmd_truncated, error_code)
                else:
                    info_without_msg = "%s %d" % (cmd, error_code)
                    if len(info_without_msg) > MAX_STRLEN:
                        error_code_str = "%d" % error_code
                        error_code_len = len(error_code_str)
                        cmd_len = len(cmd)
                        delta = cmd_len + 1 + error_code_len - MAX_STRLEN
                        cmd_truncated = cmd[:cmd_len - delta]
                        info = "%s %d" % (cmd_truncated, error_code)
                    else:
                        info = info_without_msg

    if type(fd) is type(0):
        os.write(fd, "%s\n" % info)
    else:
        fd.write("%s\n" % info)

def start_daemon(proc, pid_fd = None):
    """
    start_daemon(proc, pid_fd = None) -> exit code
    Start a daemon process. Caller must pass a function, proc(), with
    prototype looks below:
        def proc():
            return <integer>
    Please make sure the return code of proc() follows Win32 system
    error code standard.

    If pid_fd is not None, it should be a valid file object. The
    file object should point to a lock file, so we can write real daemon
    PID there.
    """
    import resource
    maxfd = resource.getrlimit(resource.RLIMIT_NOFILE)[1]
    if maxfd == resource.RLIM_INFINITY:
        maxfd = MAXFD
    # Make sure stdin, stdout and stderr are closed.
    os.close(STDIN_FD)
    os.open(NULL_TO, os.O_RDWR)
    os.dup2(STDIN_FD, STDOUT_FD)
    os.dup2(STDIN_FD, STDERR_FD)

    try:
        pid = os.fork()
    except OSError:
        msg = "start_daemon(): Failed on fork()"
        write_log(STDERR_FD, None, ERROR_PROC_NOT_FOUND, msg)
        raise ICAException(ERROR_PROC_NOT_FOUND, msg)
    if pid == 0:
        os.setsid()
        # TODO Shall we ignore SIGHUP?
        # import signal
        # signal.signal(signal.SIGHUP, signal.SIG_IGN)
        # TODO Not sure if it should be added. Ignoring child exit
        # signal can take load off icadaemon. However it looks like it's
        # supported only on Linux.
        # signal.signal(signal.SIGCHLD, signal.SIG_IGN)
        try:
            pid = os.fork()
        except OSError:
            msg = "start_daemon(): Failed on fork(), second time"
            write_log(STDERR_FD, None, ERROR_PROC_NOT_FOUND, msg)
            raise ICAException(ERROR_PROC_NOT_FOUND, msg)

        if pid == 0:
            os.chdir(WORKDIR)
            os.umask(UMASK)
            proc_params = "Daemon is running: pid:%d,uid:%d,euid:%d,gid:%d,egid:%d" % (os.getpid(), os.getuid(), os.geteuid(), os.getgid(), os.getegid())
            # Use ERR level to make sure the pid information is always
            # shown. In FreeBSD 8.2, the INFO level message does not go
            # to /var/log/message by default.
            syslog.syslog(syslog.LOG_ERR, proc_params)

            if pid_fd is not None:
                if type(pid_fd) is type(0):
                    os.write(pid_fd, "%d\n" % os.getpid())
                    os.fsync(pid_fd)
                else:
                    pid_fd.write("%d\n" % os.getpid())
                    pid_fd.flush()
                    os.fsync(pid_fd.fileno())

            # Start specific function.
            try:
                ret = proc()
            except Exception:
                import StringIO
                import traceback
                ret = ERROR_BAD_ENVIRONMENT
                exception_strfd = StringIO.StringIO()
                traceback.print_exc(file=exception_strfd)
                msg = "FATAL: Daemon got unhandled exception."
                write_log(STDERR_FD, None, ret, msg)
                for each_line in exception_strfd.getvalue().split("\n"):
                    write_log(STDERR_FD, None, ret, each_line)
                msg = "FATAL: Traceback printed. Exit gracefully."
                write_log(STDERR_FD, None, ret, msg)

            if ret != ERROR_SUCCESS:
                msg = "FATAL: proc() exit with code: %d" % ret
                write_log(STDERR_FD, None, ret, msg)
            os.exit(ret) # We should do cleanup here.
        else:
            os._exit(ERROR_SUCCESS)
    else:
        os._exit(ERROR_SUCCESS)

class ICALauncher(object):
    """
    A launcher object. It's used to create a seperated process, which
    listens to a name pipe and start process when a request is sent.

    ICALauncher uses a very simple protocol to talk with caller:

    * Caller -> launcher: 'S'<Base64 encoded serialized command line>
    * Launcher -> caller: 'E'<error code if process cannot start>
      or
      Launcher -> caller: 'R'<pid if process starts successfully>
    * Launcher -> caller: 'C'<exit code> <first line of standard output>
    """
    def __init__(self, fifo_path_read, fifo_path_write):
        self.__fifo_path_read = fifo_path_read
        self.__fifo_path_write = fifo_path_write
        self.__log_prefix = "  Launcher(pid = %d)" % os.getpid()
        try:
            # FIXME
            # I'm not sure if we should use popen instead of FIFO.
            # FIFO allows other programs send command to our daemon,
            # which saves our time when debugging. However it also
            # brings security concerns. Need discussion.
            self.__read_fifo = open(self.__fifo_path_read, 'r')
            self.__write_fifo = open(self.__fifo_path_write, 'w')
        except OSError:
            msg = "%: Failed to open FIFO" % self.__log_prefix
            write_log(STDERR_FD, None, ERROR_BAD_ENVIRONMENT, msg)
            raise ICAException(ERROR_BAD_ENVIRONMENT, msg)

    RUNNING = "R"
    ERR = "E"
    COMPLETE = "C"
    START = "S"
    FS = " "
    ERROR_PID = -1

    def __del__(self):
        self.__read_fifo.close()
        self.__write_fifo.close()

    @property
    def fifo_path_read(self):
        return self.__fifo_path_read
    def fifo_path_write(self):
        return self.__fifo_path_write

    def __write_pipe(self, msg):
        self.__write_fifo.write(msg)
        self.__write_fifo.flush()

    def start(self):
        """
        self.start(pid_fd = None) -> None

        Main loop process for a launcher.
        """
        # Just like daemon, we don't want to hold any file systems.
        os.chdir(WORKDIR)
        while True:
            request = self.__read_fifo.readline()
            if len(request) <= 2:
                msg = "%s: Bad request: %s" % (self.__log_prefix, request)
                write_log(STDERR_FD, None, ERROR_BAD_COMMAND, msg)
                self.__write_pipe("%s%d\n" % (self.ERR, ERROR_BAD_COMMAND))
                continue
            request = request[:-1] # Remove trailing '\n'
            action = request[0]
            packed_data = request[1:]
            if action != self.START:
                msg = "%s: Bad request (no prefix): %s" % \
                        (self.__log_prefix, request)
                write_log(STDERR_FD, None, ERROR_BAD_COMMAND, msg)
                self.__write_pipe("%s%d\n" % (self.ERR, ERROR_BAD_COMMAND))
                continue
            try:
                cmdline = pickle.loads(base64.b64decode(packed_data))
            except Exception:
                msg = "%s: Failed to decode: %s" % \
                        (self.__log_prefix, request)
                write_log(STDERR_FD, None, ERROR_BAD_COMMAND, msg)
                self.__write_pipe("%s%d\n" % (self.ERR, ERROR_BAD_COMMAND))
                continue
            if type(cmdline) is not type([]) or len(cmdline) < 1:
                msg = "%s: Bad command line: Invalid object" % \
                        self.__log_prefix
                write_log(STDERR_FD, None, ERROR_BAD_COMMAND, msg)
                self.__write_pipe("%s%d\n" % (self.ERR, ERROR_BAD_COMMAND))
                continue
            bin_path = cmdline[0]
            if not os.path.exists(bin_path):
                msg = "%s: executable not found: %s" % \
                        (self.__log_prefix, bin_path)
                write_log(STDERR_FD, None, ERROR_BAD_COMMAND, msg)
                self.__write_pipe("%s%d\n" % (self.ERR, ERROR_BAD_COMMAND))
                continue
            if not os.path.isfile(bin_path):
                msg = "%s: not a file: %s" % (self.__log_prefix, bin_path)
                write_log(STDERR_FD, None, ERROR_BAD_COMMAND, msg)
                self.__write_pipe("%s%d\n" % (self.ERR, ERROR_BAD_COMMAND))
                continue
            if not os.access(bin_path, os.X_OK):
                msg = "%s: Not executable: %s" % \
                        (self.__log_prefix, bin_path)
                write_log(STDERR_FD, None, ERROR_BAD_COMMAND, msg)
                self.__write_pipe("%s%d\n" % (self.ERR, ERROR_BAD_COMMAND))
                continue
            msg = "Start task: |%s|" % ICADaemon.WHITESPACE.join(cmdline)
            write_log(STDOUT_FD, None, ERROR_SUCCESS, msg)
            try:
                task = subprocess.Popen(cmdline, \
                                        stdout = subprocess.PIPE,\
                                        stderr = subprocess.PIPE)
                # We immediately return a pid back to caller, so caller
                # knows a task is started. The PID can be used by caller
                # to kill the task if needed.
                self.__write_pipe("%s%d\n" % (self.RUNNING, task.pid))

                task_return_code = task.wait()
                task_output = task.stdout.read().decode('utf-8')
                task_error  = task.stderr.read().decode('utf-8')
                msg = "%s: Task complete: %d" % \
                        (self.__log_prefix, task_return_code)
                write_log(STDOUT_FD, None, ERROR_SUCCESS, msg)

                # As per defined by spec, we return only one line from
                # standard output.
                output = task_output.split("\n")[0]
                result_to_caller = "%s%d %s\n" % \
                        (self.COMPLETE, task_return_code, output)
                self.__write_pipe(result_to_caller)
                msg = "%s: Written result through named pipe: %s" % \
                        (self.__log_prefix, result_to_caller)
                write_log(STDERR_FD, None, ERROR_SUCCESS, msg)
            except Exception, e:
                msg = "%s: Failed to launch task: %s" % \
                        (self.__log_prefix, bin_path)
                write_log(STDERR_FD, None, ERROR_BAD_COMMAND, msg)
                self.__write_pipe("%s%d\n" % (self.ERR, ERROR_BAD_COMMAND))
                continue
        return

class ICALauncherClient(object):
    """
    Implementation of client side of given launcher process. It
    generates command to a corresponding launcher process and receive
    results.
    """
    def __init__(self, fifo_path_send, fifo_path_receive, wait = True):
        self.__fifo_path_send = fifo_path_send
        self.__fifo_path_receive = fifo_path_receive
        self.__sync = wait
        try:
            self.__fifo_send = open(fifo_path_send, "w")
            self.__fifo_receive = open(fifo_path_receive, "r")
        except OSError:
            msg = "Failed to open named pipe for launcher"
            write_log(STDERR_FD, None, ERROR_BAD_ENVIRONMENT, msg)
            raise ICAException(ERROR_BAD_ENVIRONMENT, msg)

    def __delf__(self):
        self.__pipe_send.close()
        self.__pipe_receive.close()

    @property
    def synchronized(self):
        "Check if current client is working at synchronized mode."
        if self.__sync:
            return True
        return False

    @property
    def wait_fd(self):
        if self.__sync:
            return None
        else:
            return self.__fifo_receive
    @staticmethod
    def parse_response(response):
        """
        self.parse_response(response) -> code, message

        A static method to parse response from self.wait_fd().
        Note: The function will raise ICAException if response is
        illegal.
        """
        if type(response) != type(""):
            msg = "LauncherClient: Response must be a string"
            raise ICAException(ERROR_BAD_FORMAT, msg)
        if len(response) < 3:
            msg = "LauncherClient: Response has wrong length"
            raise ICAException(ERROR_BAD_FORMAT, msg)
        if response[-1] == '\n':
            response = response[:-1]
        action = response[0]
        if action != ICALauncher.COMPLETE:
            msg = "LauncherClient: Bad prefix: MUST be COMPLETE"
            raise ICAException(ERROR_BAD_FORMAT, msg)
        code_and_output = response[1:].split(ICALauncher.FS)
        if len(code_and_output) < 2:
            msg = "LauncherClient: Bad format: must be code + output"
            raise ICAException(ERROR_BAD_FORMAT, msg)
        try:
            code = int(code_and_output[0])
        except Exception:
            msg = "LauncherClient: Bad format: code field must be number"
            raise ICAException(ERROR_BAD_FORMAT, msg)
        output = ICALauncher.FS.join(code_and_output[1:])
        return code, output

    def __wait_for_task(self):
        code = ERROR_SUCCESS
        output = None
        final_result = self.__fifo_receive.readline()
        try:
            code, output = ICALauncherClient.parse_response(final_result)
        except ICAException as e:
            code = e.error_code
            output = e.msg
        return code, output

    def start_task(self, cmdline):
        """
        self.start_task(cmdline) -> pid, return_code, message

        Start running a process which executes given command line.
        Return the process ID, return code and first line of standard
        output.

        Note that for asynchronized client, this function returns
        immediately when new process is created. The return_code is set
        to 0 and message is set to None. Caller must use self.wait_fd
        property to get a file descriptor object. It can be used with
        select.select() to do IO multiplexing.

        If task is not created, e.g., the given command is not found in
        VM, the PID will be set to ICALaucnher.ERROR_PID.
        """
        task_pid = None
        packed_data = base64.b64encode(pickle.dumps(cmdline))
        sent_data = "%s%s\n" % (ICALauncher.START, packed_data)
        self.__fifo_send.write(sent_data)
        self.__fifo_send.flush()
        # Always read a line to get initial results
        initial_result = self.__fifo_receive.readline()
        initial_result = initial_result[:-1] # Remove newline
        exec_status = initial_result[0]
        if exec_status == ICALauncher.ERR:
            return ICALauncher.ERROR_PID, ERROR_BAD_COMMAND, None
        elif exec_status == ICALauncher.RUNNING:
            try:
                task_pid = int(initial_result[1:])
            except Exception:
                return ICALauncher.ERROR_PID, ERROR_BAD_ENVIRONMENT, None
        else: # Impossible
            msg = "[INTERNAL] Bad initial status: %s" % initial_result
            write_log(STDERR_FD, None, ERROR_INVALID_PARAMETER, msg)
            assert False

        if self.__sync:
            return_code, msg = self.__wait_for_task()
        else:
            return_code = ERROR_SUCCESS
            msg = None
        return task_pid, return_code, msg

class ICADaemon(object):
    """
    A daemon process to listen to serial port and process request.
    """
    __VERBS = [ "get", "set", "send" ]
    # Client FIFO is a named pipe, which allows Python script send
    # commands to icadaemon from Linux side. Useful for debugging.

    __BAD_CMD_VERB = "badCmd"
    __ICA_PLUGIN_PREFIX = "ica-"
    WHITESPACE = " "

    def __init__(self, sync_launcher_client, async_launcher_client,
                       input_channel_path):
        """
        Initialize ICADaemon environment.
        """

        self.__async_task_pid = None
        self.__sync_launcher_client = sync_launcher_client
        self.__async_launcher_client = async_launcher_client
        if not self.__sync_launcher_client.synchronized:
            msg = "Synchronized launcher is not really synchronized"
            write_log(STDERR_FD, None, ERROR_INVALID_PARAMETER, msg)
            raise ICAException(ERROR_INVALID_PARAMETER, msg)
        if self.__async_launcher_client.synchronized:
            msg = "Asynchronized launcher is actually synchronized"
            write_log(STDERR_FD, None, ERROR_INVALID_PARAMETER, msg)
            raise ICAException(ERROR_INVALID_PARAMETER, msg)


        self.__internal_noun_handlers = {
                "task": self.__on_internal_task,
                "shutdown": self.__on_internal_shutdown
                }

        self.__input_channel_path = input_channel_path
        try:
            self.__input_channel_fd = open(input_channel_path, "r")
        except OSError:
            msg = "Failed to open input channel. Bad environment"
            write_log(STDERR_FD, None, ERROR_BAD_ENVIRONMENT, msg)
            raise ICAException(ERROR_BAD_ENVIRONMENT, msg)

    def __write_response_to_host(self, noun, error_code, msg):
        """
        self.__write_response_to_host(noun, error_code, msg)

        Write response string to host.
        """
        # We got to open the same file path because serial port requires
        # this.
        try:
            channel_write_fd = open(self.__input_channel_path, "w")
            write_log(channel_write_fd, noun, error_code, msg, True)
            channel_write_fd.close()
        except OSError:
            msg = "Failed to open FIFO structure. Bad environment"
            write_log(STDERR_FD, None, ERROR_BAD_ENVIRONMENT, msg)
        return

    def __on_request(self):
        request = self.__input_channel_fd.readline()
        # NOTE: A request from Windows side may automatically add \r\n
        # sequences right after a valid request. Some experiments show
        # that it is not controlled by client code but Hyper-V serial
        # port simulation code. I can't distinguish it with an illegal
        # request from Linux side.
        #
        # So, I decide to ignore any lines that comes with only
        # newlines.
        request = request[:-1]
        if len(request) == 0 or len(request) == 1 and request[0] == '\r':
            # msg = "Empty line received. Ignore it."
            # write_log(STDOUT_FD, None, ERROR_SUCCESS, msg)
            return
        request = request.rstrip()
        verb, noun, optional_data = parse_request(request)
        if verb is None or noun is None:
            # Bad format: we return "badCmd ERROR_BAD_COMMAND"
            msg = "Bad command format: \"%s\"" % request
            self.__write_response_to_host(request, ERROR_BAD_COMMAND, msg)
            return
        verb = verb.lower()
        noun = noun.lower()
        handler = self.__internal_noun_handlers.get(noun)
        if handler is not None:
            handler(verb, noun, optional_data)
        else:
            self.__on_external_noun(verb, noun, optional_data)

    # The following __on_internal_*() methods are the internal command
    # handlers.
    def __on_internal_shutdown(self, verb, noun, optional_data):
        """
        self.__on_internal_shutdown(verb, noun, optional_data)

        Process for internal noun: task. We support the following
        command formats:
        - set shutdown action=reboot
          Return data:   shutdown 0
        - set shutdown action=poweroff
          Return data:   shutdown 0
        """
        params = parse_params(optional_data, case_sensitive = False)
        msg = None
        code = ERROR_SUCCESS
        reboot = False
        if params is None:
            code = ERROR_INVALID_PARAMETER
        elif verb == "set":
            action = params.get("action")
            if action is not None:
                action = action.lower()
                if action == "poweroff":
                    reboot = False
                    cmdline = [None, "set", "action=poweroff"]
                elif action == "reboot":
                    reboot = True
                    cmdline = [None, "set", "action=reboot"]
                else:
                    msg = "Unknown action: %s" % action
                    code = ERROR_INVALID_PARAMETER
                    self.__write_response_to_host(noun, code, msg)
                    return
                # We use an external ica-shutdown script to do this job.
                script_path = os.path.dirname(os.path.abspath(sys.argv[0]))
                task_bin = "%s%s" % (self.__ICA_PLUGIN_PREFIX, noun)
                task_bin_fullpath = os.path.join(script_path, task_bin)
                cmdline[0] = task_bin_fullpath
                code, msg = self.__start_new_task(cmdline, False)
            else:
                msg = "Missing parameter: action"
                code = ERROR_INVALID_PARAMETER
        else:
            msg = "Verb not supported: %s" % verb
            code = ERROR_INVALID_PARAMETER
        self.__write_response_to_host(noun, code, msg)
        

    def __on_internal_task(self, verb, noun, optional_data):
        """
        self.__on_internal_task(verb, noun, optional_data)

        Process for internal noun: task. We support the following
        command formats:
        - get task info=status
          Return data:   task 0 <busy|idle>
        - set task action=run,cmd=<command line>
          Return data:   task 0
        - set task action=kill
          Return data:   task 0
        """
        params = parse_params(optional_data)
        msg = None
        code = ERROR_SUCCESS
        if params is None:
            code = ERROR_INVALID_PARAMETER
        elif verb == "get":
            value = params.get("info")
            if value is not None and value.lower() == "status":
                if self.__async_task_pid is not None:
                    msg = "busy"
                else:
                    msg = "idle"
            else:
                code = ERROR_INVALID_PARAMETER
        elif verb == "set":
            action = params.get("action")
            if action is not None:
                if action.lower() == "run":
                    cmd = params.get("cmd")
                    if cmd is not None:
                        # NOTE: We don't support command line argument
                        # with spaces. However, using multiple spaces
                        # as delimiter are allowed.
                        wait = params.get("wait")
                        if wait is None:
                            wait = False
                        else:
                            wait = wait.lower()
                            if wait == "1" or wait == "yes" \
                                    or wait == "true":
                                wait = True
                            elif wait == "0" or wait == "no" \
                                    or wait == "false":
                                wait = False
                            else:
                                code = ERROR_INVALID_PARAMETER
                                self.__write_response_to_host(noun, \
                                                              code, msg)
                                return
                        cmdline = cmd.split(self.WHITESPACE)
                        cmdline = filter(lambda x: len(x) != 0, cmdline)
                        code, msg = self.__start_new_task(cmdline, wait)
                    else:
                        code = ERROR_INVALID_PARAMETER
                elif action.lower() == "kill":
                    code, msg = self.__kill_current_task()
                else:
                    # Unknown parameter
                    code = ERROR_INVALID_PARAMETER
            else:
                code = ERROR_INVALID_PARAMETER
        else:
            # Unknown verb
            code = ERROR_BAD_COMMAND
        self.__write_response_to_host(noun, code, msg)

    def __start_new_task(self, cmdline, wait = True):
        if wait:
            target_client = self.__sync_launcher_client
        else:
            if self.__async_task_pid is not None:
                msg = "A task is running: pid = %d" % self.__async_task_pid
                write_log(STDERR_FD, None, ERROR_BUSY, msg)
                return ERROR_BUSY, None
            target_client = self.__async_launcher_client
        msg = "Starting new task: |%s|" % self.WHITESPACE.join(cmdline)
        write_log(STDOUT_FD, None, ERROR_SUCCESS, msg)

        task_pid, return_code, msg = target_client.start_task(cmdline)
        if not wait:
            if task_pid == ICALauncher.ERROR_PID:
                msg = "Asynchronized task failed to start"
                write_log(STDERR_FD, None, return_code, msg)
                msg = None
            else:
                msg = "Asynchronized task starts, pid = %d" % task_pid
                write_log(STDOUT_FD, None, ERROR_SUCCESS, msg)
                self.__async_task_pid = task_pid
                msg = "%d" % task_pid
        return return_code, msg

    def __kill_current_task(self):
        if self.__async_task_pid is not None:
            msg = "%d" % self.__async_task_pid
            write_log(STDOUT_FD, None, ERROR_SUCCESS, msg)
            os.kill(self.__async_task_pid, signal.SIGKILL)
            return ERROR_SUCCESS, msg
        return ERROR_PROC_NOT_FOUND, None

    def __on_external_noun(self, verb, noun, optional_data):
        """
        self.__on_external_noun(verb, noun, optional_data)

        Process an command that should be handled by external plug-ins.
        """
        # All command processor scripts must be put under the same path
        # where icadaemonis installed.
        script_path = os.path.dirname(os.path.abspath(sys.argv[0]))
        task_bin = "%s%s" % (self.__ICA_PLUGIN_PREFIX, noun)
        task_bin_fullpath = os.path.join(script_path, task_bin)
        if not os.path.exists(task_bin_fullpath):
            msg = "Plug-in not found in VM: %s" % task_bin
            self.__write_response_to_host(noun, ERROR_BAD_COMMAND, msg)
            return
        if not os.path.isfile(task_bin_fullpath):
            msg = "Bad Plug-in: It's a file: %s" % task_bin
            self.__write_response_to_host(noun, ERROR_BAD_COMMAND, msg)
            return
        if not os.access(task_bin_fullpath, os.X_OK):
            msg = "Not executable plug-in: %s" % task_bin
            self.__write_response_to_host(noun, ERROR_BAD_COMMAND, msg)
            return

        if optional_data is None or len(optional_data) == 0:
            cmdline = [task_bin_fullpath, verb]
        else:
            cmdline = [task_bin_fullpath, verb, optional_data]
        return_code, output = self.__start_new_task(cmdline, True)
        self.__write_response_to_host(noun, return_code, output)
        return

    def __on_async_launcher_result(self):
        # We don't return any message for async tasks, so it won't mess
        # up transaction of current requests.
        if self.__async_task_pid is None:
            msg = "[INTERNAL] No task is running but got response"
            write_log(STDERR_FD, None, ERROR_BAD_ENVIRONMENT, msg)
            return
        msg = "Task complete: pid = %d" % self.__async_task_pid
        write_log(STDOUT_FD, None, ERROR_SUCCESS, msg)

        wait_fd = self.__async_launcher_client.wait_fd
        response = wait_fd.readline()
        try:
            code, output = ICALauncherClient.parse_response(response)
        except ICAException as e:
            code = e.error_code
            output = e.msg
        self.__async_task_pid = None
        # NOTE: Currently we don't write result back to host, as we
        # don't want to mess up the following requests/respones.

    def __daemon_main_loop(self):
        """
        self.__daemon_main_loop() -> error_code

        The main command processor function for handling request and
        response.
        """
        write_log(STDOUT_FD, None, ERROR_SUCCESS, "ICADaemon started")
        wait_fd = self.__async_launcher_client.wait_fd
        inputs = [self.__input_channel_fd, wait_fd]
        outputs = []
        while True:
            result_list = select.select(inputs, outputs, inputs)
            # We care about only the readable list
            readable_list = result_list[0]
            if readable_list is not None:
                for fd in readable_list:
                    fn = fd.fileno()
                    if fn == self.__input_channel_fd.fileno():
                        # We have a new request from Host Side.
                        self.__on_request()
                    elif fn == wait_fd.fileno():
                        # We have response from tasks controlled by child
                        # process.
                        self.__on_async_launcher_result()
                    else:
                        # Impossible!
                        assert False
            else:
                msg = "select.select() returns but no readable fd."
                write_log(STDERR_FD, None, ERROR_NO_MORE_FILES, msg)
                return ERROR_NO_MORE_FILES

    def start(self, daemon_mode = True, pid_fd = None):
        """
        self.start(daemon_mode = True) -> None
        Start daemon process. After this function, the current process
        is in daemon mode.

        If daemon_mode is set to False, ICADaemon will be running as a
        regular process instead of daemon. It's useful for debugging
        icadaemon issues.
        """
        if daemon_mode:
            start_daemon(lambda: self.__daemon_main_loop(), pid_fd)
        else:
            if pid_fd is not None:
                if type(pid_fd) is type(0):
                    os.write(pid_fd, "%d\n" % os.getpid())
                    os.fsync(pid_fd)
                else:
                    pid_fd.write("%d\n" % os.getpid())
                    pid_fd.flush()
                    os.fsync(pid_fd.fileno())
            self.__daemon_main_loop()
