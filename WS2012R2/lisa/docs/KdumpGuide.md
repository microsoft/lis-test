# Kdump Test Suite Guide

### Introduction
This document is intended as a guide for configuring kdump, describing general and particular cases.

#### Kdump workflow

##### General configuration

  - We recommend to use crashkernel size to 384M in grub.cfg (`crashkernel=384M`). We use this value because some versions of LIS and distributions use more than 128M or 256M.
  For troubleshooting purposes you can try to use 512M.
  - Set the default behavior to reboot in kdump.conf
    + `default reboot`
  - Make sure path param is not commended in kdump.conf
    + `path /var/crash`
  - Make sure kexec is not loaded
  - Enable kdump
    + `chkconfig kdump on`; `USE_KDUMP=1` in /etc/default/kdump-tools for Ubuntu
  - Reboot the system

##### After configuration

  - After configuration make sure kdump memory is loaded and kdump is active:
    + `cat /sys/kernel/kexec_crash_loaded` should be equal to 1
    +  if you use crashkernel=384M `cat /sys/kernel/kexec_crash_size` should return 402653184
    +  if you use crashkernel=256M `cat /sys/kernel/kexec_crash_size` should return 268435456
  - Enable all functions for sysrq
    + `echo 1 > /proc/sys/kernel/sysrq`
  - If you want to do kdump through NMI, enable NMI panic
    + `sysctl -w kernel.unknown_nmi_panic=1`
  - If everything is set, trigger the crash
    + `echo c > /proc/sysrq-trigger`
  
##### After the crash

Here the following behaviors can be observed.

The expected one should be this: VM should panic and after a few moments, VM should reboot and write the dump files in the path that was set in kdump.conf (default /var/crash). Memory dump files can be analyzed with the crash utility.

Bad behavior would be: 
  - VM does panic but never reboot. Heartbeat is in LostCommunication state. In this case kdump is not working correctly.
  - VM does panic and reboot but dump files are not written.

### Considerations

- On a Generation 2 VM, the VM console screen does not get updated, therefore the reboot is not seen but it actually takes place in background and the dump files are written. A serial console can be attached to the VM in order to obtain the crash messages.

- In some cases the VM does not reboot but the serial console log may show that we can use the noapic option in grub, and this solves the problem.

- On a SMP configured VM, a crash operation can be triggered on any desired CPU core by using the following command:
  + `taskset -c 3 echo c > /proc/sysrq-trigger`

#### For RHEL 5.2 to 5.8 and 6.0 to 6.2
  - These versions require special configuration which can be found here: https://support.microsoft.com/en-us/kb/2858695 . These steps and general configuration should be done before LIS installation.
