# Setting Up a Unified Open vSwitch Architecture with Netplan and Libvirt on Debian 13

This comprehensive blueprint outlines how to build a highly flexible, enterprise-grade virtual network infrastructure on a 4-NIC mini server using a **single, unified Open vSwitch (OVS) bridge**. 

By consolidating all physical ports into one software-defined switch, you gain maximum flexibility to mix LACP link aggregation, external network tags, and strict internal-only test environments completely inside software.

## 1. Prerequisites and Installation

Install the required packages for Netplan, Open vSwitch, and the KVM virtualization management stack on Debian 13:

```bash
sudo apt update
sudo apt install -y netplan.io openvswitch-switch openvswitch-common qemu-kvm libvirt-daemon-system virtinst
```

*Note: If OVS is installed but not declared in your Netplan configurations, it will remain completely idle. Your networking will function as standard, simple interfaces using default kernel renderers.*

---

## 2. Complete Unified Netplan Configuration

Create or replace your Netplan layout file (e.g., `/etc/netplan/01-netcfg.yaml`). 

This master configuration pools your physical NICs, aggregates two ports into an LACP bond for bandwidth and redundancy, leaves other ports open for alternate uplinks, and provisions a secure host hypervisor management interface tagged natively on **VLAN 10**.

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    # Primary infrastructure bundle links
    eth0:
      dhcp4: false
      dhcp6: false
    eth1:
      dhcp4: false
      dhcp6: false
    # Secondary uplink or DMZ edge links
    eth2:
      dhcp4: false
      dhcp6: false
    eth3:
      dhcp4: false
      dhcp6: false

  # Define structural link aggregation directly inside the OVS layer
  bonds:
    bond0:
      interfaces: [eth0, eth1]
      parameters:
        mode: 802.3ad
        lacp-rate: fast
        transmit-hash-policy: layer2+3
      openvswitch: {}

  # The single, master virtual switch fabric
  bridges:
    ovs-br0:
      interfaces: [bond0, eth2, eth3]
      openvswitch: {}

  # Logical interfaces mapping the host hypervisor back to the network
  vlans:
    # Hypervisor Host Management access restricted to secure VLAN 10
    mgmt10:
      id: 10
      link: ovs-br0
      addresses:
        - 192.168.10.100/24
      routes:
        - to: default
          via: 192.168.10.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

### Apply and Verify the Network
Test the configuration file safely before committing changes to avoid losing connectivity:

```bash
sudo netplan try
sudo netplan apply
```

Verify that the single unified bridge, physical ports, and link aggregation bundles are operational:

```bash
sudo ovs-vsctl show
```

---

## 3. Configure the Libvirt Network with Friendly Portgroups

Instead of typing hardcoded tags for every single VM deployment, define an XML network abstraction containing logical aliases (**portgroups**). This includes an isolated, host-only tag loopback system (e.g., **VLAN 99**) for test networks like a firewall LAN. Because VLAN 99 traffic is never routed to a physical uplink port, its traffic stays completely inside hypervisor memory at bus speeds.

Create a network configuration file named `ovs-trunk-network.xml`:

```xml
<network>
  <name>ovs-trunk-network</name>
  <forward mode='bridge'/>
  <bridge name='ovs-br0'/>
  <virtualport type='openvswitch'/>
  
  <!-- Standard Internal Office / Home VM Traffic -->
  <portgroup name='trusted-vlan10'>
    <vlan><tag id='10'/></vlan>
  </portgroup>

  <!-- External or DMZ Facing Public Services -->
  <portgroup name='dmz-vlan20'>
    <vlan><tag id='20'/></vlan>
  </portgroup>

  <!-- Isolated Test Network (LAN side of Firewalls / Sandboxes) -->
  <portgroup name='isolated-test-lan'>
    <vlan><tag id='99'/></vlan>
  </portgroup>
</network>
```

Register, start, and configure this logical switch network to mount at boot time:

```bash
sudo virsh net-define ovs-trunk-network.xml
sudo virsh net-start ovs-trunk-network
sudo virsh net-autostart ovs-trunk-network
```

---

## 4. Provisioning VMs via virt-install

When deploying virtual appliances or test clients, reference the shared network profile and choose your isolation zone instantly using the targeted portgroups.

### Deploying a Test Firewall VM (Trunk WAN + Isolated LAN)
This builds a firewall node equipped with two interfaces. The first picks up full VLAN trunking tags (WAN/Uplinks), and the second binds directly into your host-contained test LAN loopback pool:

```bash
virt-install \
  --name test-firewall \
  --ram 2048 \
  --vcpus 2 \
  --disk size=15,format=qcow2 \
  --os-variant freebsd14.0 \
  --network network=ovs-trunk-network,virtualport_type=openvswitch \
  --network network=ovs-trunk-network,portgroup=isolated-test-lan \
  --graphics none
```

### Deploying a Protected Test Client VM
This provisions a standard client machine locked safely inside the logical sandbox. It can only talk to the internet or fetch a local IP if your test firewall instance is online and running routing/DHCP rules:

```bash
virt-install \
  --name test-client-vm \
  --ram 2048 \
  --vcpus 1 \
  --disk size=10,format=qcow2 \
  --os-variant debian12 \
  --network network=ovs-trunk-network,portgroup=isolated-test-lan \
  --graphics none \
  --console pty,target_type=serial \
  --location http://debian.org \
  --extra-args "console=ttyS0"
```

---

## 5. Traffic Shaping and QoS Tuning

Because all data flows through a single centralized virtual bridge infrastructure, you can prevent specific test networks or heavy nodes from overwhelming the physical uplinks.

### Direct Ingress Traffic Policing on individual VM slots
To apply a strict rate-limit directly to a virtual interface (e.g., hard-capping a test client port to 50 Mbps bandwidth with a 10 Mbps burst buffer), execute:

```bash
# Rate values are configured in kbps
sudo ovs-vsctl set interface vnet0 ingress_policing_rate=50000
sudo ovs-vsctl set interface vnet0 ingress_policing_burst=10000
```

---

## 6. Official Reference Documentation

* Netplan YAML Configuration Guide: https://readthedocs.io
* Canonical Netplan OVS Sample: https://github.com
* Open vSwitch Project Documentation: https://openvswitch.org
* Libvirt Network XML Format Guidelines: https://libvirt.org
