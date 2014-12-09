.. This is document written in reStructuralText format. Please use
.. docutils tool to compile it to common used formats such as HTML or
.. rtf.

========================
ICADaemon Documentations
========================

ICADaemon is a library to provide tools and functions for ICA test
automation. It's designed to provide a daemon process, which runs
on a Linux/FreeBSD VM hosted by a Windows Server Hyper-V host.

ICADaemon allows test automation retrieve information of Linux/FreeBSD
VM through virtual serial port (or named pipe, from Windows side).

NOTE: The FreeBSD support is under development.

Build and Install Package
=========================

All ICATest modules and tools are checked in to ICA test automation
respository. You may get it from ``$ICA\trunk\ica\tools\icaserial``.

There's no need to compile code, as all tools are written in Python.

The ICATest is constructed as standard Python distribution package. You
can use command line below from ``$ICA\trunk\ica\tools\icaserial`` to
generate tarball or zip packages.

::

   python setup.py sdist --formats=gztar,zip

To install the package to Linux VM, you need to copy the tarball to a
Linux box, extract it and install it with command line below:

::

   tar xfz icatest-{version}.tar.gz
   cd icatest-{version}
   python setup.py install

After installation, all executable scripts, including ``icadaemon``,
``icalauncher`` and plug-ins will be installed to /usr/bin by default.
It will also install ``icatest`` module to ``site-packages`` folder of
your Python installation.

A complete package installation provides the following scripts:

* ``setup.py``: Setup scripts to create
* ``bin\icadaemon``: The major daemon process that listens to serial port.
* ``bin\icalauncher``: Helper tools launched by ``icadaemon``.
* ``bin\ica-*``: Plug-in scripts as external commands.
* ``icatest``: Python module to provide functionalities.
* ``icaserial.ps1``: Powershell script as client, running at Windows side.

A Quick Start
=============

Before you start, please make sure you have a Linux VM deployed. Don't
forget defining named pipe for COM2 port.

After installing the package, log on as root user to VM and run command
line below:

::

  icadaemon

This will start a daemon process, which listens to request sent from
COM2 port, that is, ``/dev/ttyS1`` from Linux side or a named pipe
defined from Hyper-V management console.

Since ``icadaemon`` is a daemon process, it does not generate any output
to console. That may cause big issues for debugging. However, you can
check ``icadaemon`` logs to get execution information. Please check
section, `Developer Support` for more information.

Let's assume you have defined a named pipe, ``TestVM-com2`` for
a VM, ``TestVM``, then you can start a daemon

Copy ``icaserial.ps1`` to the Hyper-V host that hosts the VM. Start a
PowerShell command line prompt with administrator mode. Run command below
to retrieve the IPv4 address of a specified MAC address. NOTE: You need
to replace the ``11:22:33:44:55:66`` with a assigned MAC address in your
VM.

::

  .\icaserial.ps1 -Pipe TestVM-com2 -Command "get ipv4 macaddr=11:22:33:44:55:66"

``Icaserial.ps1`` also supports remote mode, so the command can
basically run from any Windows 7 or Windows Server 2008 R2 box if
the target Hyper-V server has WinRM (remote management) enabled. Use
``-VMHost`` parameter to do this job:

::

  .\icaserial.ps1 -VMHost TestVM-Host -Pipe TestVM-com2 -Command "get ipv4 macaddr=11:22:33:44:55:66"

Or, more specificly, user may also specify a timeout. Note that
``icaserial.ps1`` waits for 5 seconds if ``-Timeout`` parameter is not
given in command line.

::

  .\icaserial.ps1 -VMHost TestVM-Host -Timeout 5 -Pipe TestVM-com2 -Command "get ipv4 macaddr=11:22:33:44:55:66"


When the command is successfully complete, you may see an output like
below:

::

  ipv4 0 172.22.143.74

Or, if anything wrong happens, for example, you specified a wrong MAC
address, you may see errors like below:

::

  ipv4 2 MAC address not found: 00:15:5D:8F:0C:4A


You may also try to launch an asynchronized command by command below:

::

  .\icaserial.ps1 -Pipe LisFedoraX64-2-COM2 -Command "set task action=run,cmd=/bin/ls -l"

You may see a response like below (``1960`` represents new process ID):

::

  task 0 1960

You may also query the status of a running task:

::

  .\icaserial.ps1 -Pipe LisFedoraX64-2-COM2 -Command "get task info=status"

A response may look like below:

::

  task 0 idle


That's it! Just go ahead and have a try.


Protocol
=========

The public command line interface is ``icadaemon``. It starts a daemon
process, which runs in background and listen to COM2 port
``/dev/ttyS1`` from Linux VM side.

You may try run ``icadaemon`` in ``/etc/rc.local`` file to make sure it
can access all resources of VM box.


``Icadaemon`` accepts a request in plain string format like below:

::

  Request ::= <OptFS><Verb><FS><Nouns><FS><OptionalData><OptFS><NewLine>
  FS      ::= One or more whitespaces
  OptFS   ::= Zero or One or more whitespaces
  Verb    ::= get|set|send
  Noun    ::= <InternalCommands> | <ExternalCommands>
  NewLine ::= '\n'
  OptionalData ::= ((<Key>=<Value>)?,)*
  Key     ::= [\d\w\,\=\\]+
  Value   ::= [\d\w\,\=\\ ]+

  InternalCommands ::= task
  ExteranlCommands ::= ipv4|datetime|ostype|shutdown|tcstatus

A request string uses newline token as the end of request. That is,
``icadaemon`` does not accept newlines in request.

`NOTE`: As per required by ICA/LiSA test framework, ``icadaemon``
automatically ignores trailing whitespaces in ``<OptionalData>`` field.
However, this behavior introduces a side effect. When users want to pass
a string with trailing whitespaces to a command, they whitespaces may be
eaten by ``icadaemon``. For example:

::

  "set task action=run,cmd=/bin/rm -f file_with_trailing_whitespaces    "

The whitespaces after ``file_with_trailing_whitespaces`` is ignored by
``icadaemon``.

This behavior does not affect current supported commands. However, if
developers really want ``icadaemon`` accept trailing whitespaces, they
can do it by appending a comma at the end of whitespaces:

::

  "set task action=run,cmd=/bin/rm -f file_with_trailing_whitespaces    ,"

In the cases above, the whitespaces before the last comma are accepted
by ``icadaemon`` (but still ignored by ``task`` command handler for now).

After receiving a request, ``icadaemon`` generates a command line based
on the request and execute it. After execution, it returns a response
like below:

::

  Response ::= <Noun><FS><Status><FS><OptionalData><NewLine>
  FS       ::= One-character whitespace
  Status   ::= Standard Win32 error code
  OptionalData  ::= One line string from execution of command

Just like the request, response uses newline token as the end of
response.


``Icadaemon`` does not allow processing more than one command at the
same time. When a user sends the second request while the first one is
under processing, the request is simply pending until ``icadaemon``
sends the response of first command.

Specific to implementation, a typical transaction works like below:

  * Client sends a request through named pipe.
  * Client listens to named pipe for response.
  * ``Icadaemon`` receives request and generate results.
  * Client gets response.


Internal and External Commands
==============================

``Icadaemon`` has two kinds of commands: internal and external. An
internal command is defined within ``icadaemon`` code, while an external
command is defined as an executable file in Linux file system.

When receving a request, ``icadaemon`` always checks if given request is
for running an internal command first. If yes, it executes an internal
command. If not, it looks for a matching external command. If it's
found, it will generate a command line and execute it. When an
internal and external commands have the same name, only internal command
is picked up.


Internal Commands
=================

Currently ``icadaemon`` supports two internal commands, ``task`` and
``ica-shutdown``.

Task command
------------

The ``task`` command is to start an asynchronized process in Linux VM.
It's monitored by ``icadaemon``. When a task is started successfully, it
returns a ``"task 0 <PID>"`` string (0 = ERROR_SUCCESS) as response to
indicate the process is started. Format looks like below:


* Start a new task. When the return code of response is 0, it follows
  with a PID to indiciate a new process is started successfully. If the
  return value is 22 (ERROR_BAD_COMMAND), it means the command line
  passed to server it invalid. If the return value is 9
  (ERROR_BAD_ENVIRONMENT), it means there may be a bug in icadaemon,
  which cause internal communication fail to complete.

::

 set task action=run,cmd=<your command line>
 task 0 1960
 task 22

`NOTE`: In this version, ``task`` command does not support escaping
whitespaces. That is, it's impossible to launch a task to remove a file 
with whitespaces in file name.

* Start a new task and wait until it exits. This will be useful if
  SDETs care about the exit code of running task. This behavior is
  activated only when a task command is sent with ``wait`` attribute is
  set:

::

 set task action=run,cmd=<your command line>,wait=true
 task <exit code> <first line response>
 set task action=run,cmd=<your command line>,wait=1
 task <exit code> <first line response>
 set task action=run,cmd=<your command line>,wait=yes
 task <exit code> <first line response>
 task 87

``NOTE`` The `wait` attribute accepts three values must-wait:
``true``, ``1`` and ``yes``, while ``false``, ``0`` and ``no`` are
treated as no-wait. Any other values are treated as invalid value, which
will return error code 87. If the attribute is omitted, the task is run
in asynchronized manner.

``NOTE`` The `wait` attribute may be dangerous, that it make the icadaemon
non-responsive if a command must run for a long time. Use it at your own risk.

* Get information of new task. The task asks ``icadaemon`` if a task is
  currently running. If yes, the response will set optional data field
  as "busy". Or, if no task is running, the response will come with
  optional data field set to "idle".

::

 get task info=status
 task 0 busy
 task 0 idle

* Kill a running task. If a running task is in progress, it will be
  killed, and response will has optional data field as the PID of killed
  process. Or, if no task is running, the return value of response is
  set to 127 (ERROR_PROC_NOT_FOUND), to indiciate no process is killed.

::

 set task action=kill
 task 0 1960
 task 127

``icadaemon`` does not allow running a second task while the first one
is running. However, it still allows you to run external commands or
querying status of running tasks with internal commands.

Note that when an asynchronized task is complete, ``icadaemon`` WILL NOT
RETURN the exit code. This is because we don't want an response report
from earlier task mess up the current transactions.

Shutdown command
----------------

Shutdown command is used to perform a shutdown or reboot operation
against VM. Format:

::

  set shutdown action=poweroff
  set shutdown action=reboot

Users may notice there's an ``ica-shutdown`` script in ICADaemon
package, which supposed to provide the same functionalities with
``shutdown`` command. Please check the description of ``ica-shutdown``
script (see below) to get more details.

External Commands
=================
When processing an external command, ``icadaemon`` follows the rules
below to generate command line:

::

  Assume request is <Noun><FS><Status><FS><Message><NewLine>
  Generated command line: ica-<Nouns> <Verb> <OptionalData>

For example, when we want IPv4 address of given network adatper, we may
use command line below:

::

  .\icaserial.ps1 -Pipe TestVM-com2 -Command "get ipv4 macaddr=11:22:33:44:55:66"

``Icadaemon`` generates a command line like below:

::

  ica-ipv4 get macaddr=11:22:33:44:55:66

There must be an executable ``ica-ipv4`` file, either script or binary,
exists under the same path of ``icadaemon`` script, which takes this
command line and give results. The executable files, are called
`Plug-ins`.

NOTE: I add ¡°ica-¡° prefix, so we can avoid name conflict with other 
built-in system executable files.

A ``Plug-in`` file must follow the rules below:

 * It must be a executable file, no matter scripts or binaries.
 * It must support one action from ``get``, ``set`` and ``send`` as first parameters.
 * It must support parameter format: ``param2=value2,param2=value2,...``.
   The ``=`` and ``,`` tokens should not have whitespaces around.
 * It must print response to standard output. ``Icadaemon`` picks the
   first line of standard output as the ``optionalData`` field in
   response.
 * It must use standard Win32 error codes as exit code.

 NOTE: If a plug-in is written in script, please make sure the file
 format is set to UNIX style (use '\n' as newline). Without this,
 all scripts will fail when being executed on Linux/FreeBSD because
 CSH/Bash always report failures.

ICADaemon package provides modules, ``icatest.errors`` to define
common used Win32 error codes. Developer may also use function,
``icadaemon.daemon.parse_params()`` to parse parameters.

Pleas also note the response should be one line. Although a ``plug-in``
can write multiple lines, ``icadaemon`` only takes the first line as
resonse.

With the rules above, developers can extend the external command set 
by writing more executable files.

Built-in Plug-ins
=================

``ICADaemon`` packages provide some built-in plug-in scripts to allow
SDETs retrieve information for test execution. The supported plug-in
list is below:

* ``ica-ipv4`` Query IPv4 address of given network adapter.
* ``ica-tcstatus`` Query status of current running ICA test cases.
* ``ica-ostype`` Query type of current operating system.
* ``ica-datetime`` Query and set system date and time.
* ``ica-shutdown`` Invoke a shutdown command to power off system.

IPv4 Plug-in
------------

This plug-in allows querying IPv4 address of a specified network
adapter. Supported request format:

::

  get ipv4 macaddr=11:22:33:44:55:66
  get ipv4 macaddr=112233445566

A typical returned response will look like below:

::

  ipv4 0 192.168.0.1
  ipv4 0 192.168.0.1,10.0.0.7

The second response may happen when a network adapter has more than one
network adapters. In this case, all IP addresses assigned to the same
adapter will be returned, seperated with comma.

We don't support setting a new IPv4 address for now.

TCStatus Plug-in
----------------

This plug-in allows querying ICA test case execution status. It simply
checks existence of /root/state.txt file, and return the first line of
its content. Supported request format:

::

  get tcStatus

An result of possible response looks like below:

::

  tcstatus 0 TestComplete
  tcstatus 0 TestRunning
  tcstatus 0 TestAbort

Please note that the strings after return code come from the first line in
``/root/state.txt``. The content of is controlled by ICA test automation
script. That is, TCStatus plug-in does not guarantee the returned
string to be one of above.

Also, the return code is set to 0 (ERROR_SUCCESS) when the content of
``/root/state.txt`` is readable. It does not indicate the execution 
status of current test case.

OSType Plug-in
--------------
This plug-in allows querying name of current operating system. It
basically returns the standard output of ``uname -s`` command. Supported
request format:

::

  get OSType

A returned value looks like below:

::

  ostype 0 FreeBSD

DateTime Plug-in
----------------
This plug-in allows querying or setting system date and time. Supported
request format:

::

  get dateTime
  set dateTime datetime=HHMMmmddyyyy

When a query is processed successfully, the returned string depends on
the printed message of ``date`` command, which means it's platform
dependent. Please note the behavior may be change in the future
versions.

::

  datetime 0 <datetime value in fixed format, HHMMmmddyyyy>
  datetime <errorCode> <error message>

Shutdown plug-in
================
This plug-in allows triggering a reboot or poweroff operation against
a VM. Supported request format:

::

  set shutdown action=poweroff
  set shutdown action=reboot

The shutdown operation is always delayed for ten seconds. So Windows may
receive response before the VM actually shutdown.


`IMPORTANT NOTE:` Users may have noticed that there are two shutdown 
commands provided by ICADaemon. One is an internal ``shutdown`` command,
which is implemented in daemon.py, the other is ``ica-shutdown`` plug-in.
Indeed, the internal shutdown command does nothing but simply calls an
``ica-shutdown`` plug-in. The reason is we want a shutdown operation to
be asynchronized, while all external plug-ins are synchronized. If we
allow caller directly calls ``ica-shutdown`` plug-in, the Windows side
may raise a pipe reading error because the serial port in Linux side is
closed unexpectedly when test code in Windows side is still waiting at
the other end of named pipe.

A trick here is caller can never directly call ``ica-shutdown`` plug-in
by sending request through named pipe/serial port. Since the
internal ``shutdown`` command has the same name with the plug-in, it
always shadow the external edition, because ICADaemon treats internal
commands with higher priority.

The implementation also introduces a side effect, that you can't run
``task`` command when a ``shutdown`` is on-going. However it works


Developer Notes
===============

Developers (including plug-in writers) may access functions and tools in
``icatest`` module, which is insatlled when ICADaemon package is
installed.

One-instance Support
--------------------

``Icadaemon`` uses a lock file to make sure there's only one instance
running in system. It uses ``/var/run/icadaemon.pid`` as a lock file. When
a icadaemon starts, it checks if this file exists. If yes, it exits with
error message "an instance is still running".

Besides ``/var/run/icadaemon.pid``, ``icadaemon`` also creates four
named pipes under ``/var/run/icadaemon_launcher_*``. These named
pipes are for communication between ``icalauncher`` and ``icadaemon``.

The lock file also keeps the PID of running icadaemon, so developer can
kill the process if needed.

Meanwhile, we have other two pid files for launcher processes:
``/var/run/icalauncher_sync.pid``, and ``/var/run/icalauncher_async.pid``.
Just like ``icadaemon.pid``, they keep the launcher processes used by
``icadaemon`` for process execution.

NOTE: DO NOT DELETE these files manually! They are designed to be
handled by ``icadaemon``. If any of the files above is missing, it may
cause unpredictable results.

Request Processor
-----------------

``Icadaemon`` does not handle commands itself. As per description above,
all external commands (plug-ins) are executable scripts, while internal
commands are processed by either plug-ins or child processes. We need
to launch child processes to handle requests.

When a new ``icadaemon`` instance starts, it forks two ``icalauncher``
processes, which accepts requests from ``icadaemon``, launches
corresponding child processes and collects command output for 
``icadaemon``. One ``icalauncher`` is for handling external commands,
while the other one is for handling internal commands. ``Icadaemon`` makes
sure that every time we have only one external command and one internal
command being processed.


Logging System
--------------

``Icadaemon`` writes execution logs to ``syslog`` infrastructure. For
Linux system, you may get the logs from ``/var/log/messages``, starting
with prefix ``icadaemon`` and ``icalauncher``.

Another way to see logs generated by ``icadaemon`` is to start daemon
with command line: ``icadaemon debug``. It allows ``icadaemon`` starting
as a regular process, which writes logs to both standard output and
``syslog``.


Known Issues
============

* We need implementation for ipv4 command (icatest\freebsd.py).

* In FreeBSD there's an issue that the ``icadaemon`` process is not
  shown in output of ``ps aux``. It does not happen in Linux. This is
  not a bug of ICADaemon but a problem of ``ps`` command in FreeBSD. The
  ``ps`` tool shipped with FreeBSD always keeps output as 80 columns.
  When it sees a process with a long command line like ICADaemon, it
  truncates the outputs, so we can see only command lines like
  ``/usr/local/bin/...``. A workaround is to check ``/var/log/messages``
  logs. When ICADaemon starts, it writes a line in system log with the
  PID. Also, if you see a ``/var/run/icadaemon.pid`` file, that means a
  icadaemon instance is running.

*  ``Icadaemon`` exits on SIGHUP. This is required by RHEL/Fedora
    platform. Some investigations shown that when running ``shutdown``
    in RHEL/Fedora, ``icadaemon`` receives a SIGHUP instead of
    SIGTERM. I haven't found any documents for this behavior, but if we
    don't handle SIGHUP, our process will be killed directly without
    proper cleanup steps (removing file lock or named pipes), which
    causes our daemon fail to start after reboot.

* FreeBSD 8.2 on Hyper-V does not support request string with more than
  382 characters. Some experiments show that if a request contains more
  than 382 characters, ``icadaemon`` will not receive it through serial
  port. Linux does not have this issue.

* Current ``icadaemon`` implementation does not handle shutdown messages
  properly in OpenSUSE. It causes problems when users simply add
  ``icadaemon`` command line in ``/etc/rc.d/boot.local``. When system
  shuts down, the temporary files used by ``icadaemon`` will not be
  deleted. These files cause ``icadaemon`` fail to start after reboot,
  because it incorrectly assumes an existing ``icadaemon`` instance is
  running. We have a workaround, that we can add one more line in
  ``/etc/rc.d/boot.local`` file to delete ``/var/run/icadaemon*`` files
  before starting ``icadaemon``. However, a complete fix is to provide a
  daemon monitoring script, like all standard daemon processes, so OS
  can properly kill daemon process.

  NOTE: The problem has been fixed by using ``/etc/init.d/icadaemon``
  script installed with our package. It follows requirements from
  Linux Standard Base, which registers itself to runlevel 2, 3 and 5.
  Note the support for FreeBSD is not implemented yet.


ChangeLog
=========

* Nov. 4, 2011

  First edition is checked in by fuzhouch.

* Nov. 5, 2011

  - Daemon.py: Rewrite request/response parsing logic. Allow multiple
    whitespaces as request/response delimiter.
  - Icadaemon: disable echo mode for TTY, so Windows client does not
    need to drop original request string when receiving response from
    named pipe.
  - Icadaemon starts icalauncher with standard output redirected to
    /dev/null, so it won't mess up standard output.
  - Icaserial.ps: Remove three-line ReadLine() to keep compatible with
    icadaemon.
  - Ica-ipv4: Fix an typo that causes incorrect output message.
  - README.txt: Add descriptions for built-in plug-ins.
  - Freebsd.py: Add correct stty command to disable echo mode for FreeBSD.
  - Daemon.py: Correct deadlock problem in FreeBSD.
  - Icadaemon: Adjust atexit() handler to make it handle deadlock.

* Nov. 8, 2011

  - Update one-instance check logic. We use a ``/tmp/icadaemon_lock``
    as a file lock to make sure there's one and only one icadaemon
    process running.
  - Allow ``icadaemon`` exit on SIGHUP.

* Nov. 11, 2011

  - Daemon.py: Revise ``icatest.daemon.parse_params()`` to allow escape
    tokens. Now we can use backslash to escape special characters like
    comma and equal token.
  - Icadaemon: Rename PID file. It's now ``/var/run/icadaemon.pid`` to
    follow UNIX conventions. All temporary files are moved to ``/var/run``.
    NOTE: the named pipes used by ``icadaemon`` and ``icalauncher`` are
    unlinked right after they are created, so none of them can be seen.
  - Ica-datetime: Now it rerurns response with the same format of input,
    ``HHMMmmddyyyy`` on "set" command.

* Nov. 21, 2011

  - Icadaemon and icalauncher: Fixed an important bug, which causes
    ``icadaemon`` crash when running from ``/etc/rc.local`` in FreeBSD.
    This fix introduces a behavior change, that ``icalauncher`` processes
    become daemon now. Also, the launch time of ``icadaemon`` become a
    little bit slower, because it has to wait for process ID information
    from ``icalauncher`` before accepting requests.
  - The named pipes used for communication between ``icadaemon`` and
    ``icalauncher`` now exist under ``/var/run``. They will be removed
    until ``icadaemon`` exits. This is needed because the execution
    sequence of ``icadaemon`` and ``icalauncher`` may change, since both
    of them are daemon processes.

* Dec. 9, 2011

  - Add a ``wait`` attribute for internal task command, which allows
    ``icadaemon`` execute a command from Linux and waits for its end.
    Please note that this may be a high risk task, as ``icadaemon``
    hangs if the command takes a long time to be executed.

* Dec. 20, 2011

  - Now we have proper service management script for ``ICADaemon`` under
    ``/etc/init.d/icadaemon``. When running ``setup.py``, we can detect
    if current system supports System V style service management
    structure. If yes, it copies correct script to ``/etc/init.d`` and
    run ``chkconfig --add icadaemon`` command to configure our daemon
    running under correct run-level. Note, the script supports only
    System V style.

.. vim:ft=rst expandtab shiftwidth=4
