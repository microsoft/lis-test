# LIS Networking Automation

### Introduction
This document is intended as a guide to LIS framework’s networking scripts. The contents of this document will pertain to general configuration advice of both the host computer and the guest virtual machines running a Linux distribution.
For per-script information please consult the header of each script, as it contains more detailed information.

### Host
- Before starting the tests, the host needs to have configured at least 3 vSwitches (External, Internal and Private)
- The names of these switches will be filled inside the xml in the ‘NIC’ parameter.
- All switches must be running in Untagged mode.
- At least one of the External or Internal Switches needs to have a DHCP Server present on its network (or running its own) in order for the ConfigureNetwork test to pass. All other tests do not require a DHCP server handing out addresses, but it is more convenient to have one still.
- The Internal switch needs to be configured. This is usually done by setting a static address and netmask (unless running a DHCP server), and then filling that information in the pertinent fields inside the xml.
- No firewall rule must interfere with these tests. This includes, but is not limited to, allowing ICMP traffic, both incoming and outgoing.

### Guest
###### General setup
- Linux guests need to ensure that they have the hv_netvsc kernel module
- the LIS Framework requires a network connection to the guest in order to send commands. The network tests will ignore this interface when running the tests. This NIC is identified by the ipv4 parameter set inside the constants.sh file (sent by the LIS framework to the guest)
- it must be ensured that this NIC (used by the LIS connection) is always brought up inside the VM by the network service (by having a configuration file defined for it, e.g. ifcfg-eth0 in case of RHEL distributions)
- it is preferred to disable Network Manager manually before running the tests. Otherwise, set the NM_DISABLE=yes parameter inside the xml.
- the guest must ensure no firewall rules interfere with the tests
- when using the ‘NIC=’ parameter and setting a MAC Address, please ensure that it is not colliding with another MAC on the same host (it needs to be outside the dynamic MAC Address pool and also different from any previously set static MAC Addresses)
- NET_UTILS.ps1 contains a function that determines a valid, random and unused MAC Address
- When setting the static address for the ConfigureNetwork script, make sure it is not colliding with another IPv4 on that same network (the DHCP server is leasing out addresses on that network, so either choose one outside the DHCP pool, or set the static address that the DHCP server would lease out to this machine)

**For Copy Large File and Jumbo Frames to work:**
- The Identity file must be present in the /root/.ssh folder on both VMs, with permission 600. This needs to be specified in the XML (SSH_PRIVATE_KEY)
- You need to manually specify in the XML an IP for the second VMs test interface. This must be in the same range and same netmask as the main NIC.

**For Legacy adapter:**
- The VM must be set with either 1 vCPU or have the irqbalance / irqbalancer daemon stopped inside the VM.

###### Notes for RHEL 5 and RHEL 6:
- It is strongly recommended to disable Network Manager
- Delete NET rules (/etc/udev/rules.d/70-persistent-net.rules)
- Be sure to have only one ifcfg file, ifcfg-eth0 with dhcp enabled (https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Deployment_Guide/s1-networkscripts-interfaces.html). This will be used by LISA

**In the XML the commented parameters are optional, these can be used in case something goes wrong (DHCP server is down or allcoates IP from a different range, in which case some tests does not work)**
