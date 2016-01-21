# Copyright 2016 Steven A. Burns, Jr.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Adds the base PowerCLI cmdlets
Add-PSSnapin VMware.VimAutomation.Core

# Default variables
$csvfile = "D:\test.csv"
$vmhost  = "192.168.1.30"
$ds      = "datastore2"
$df      = "Thin"
$ovf     = "D:\vm_images\centos5\centos5.ovf"
$gu      = "root"
$gp      = "testlab2016"

# VM Startup timeout in seconds
$maxTimeOut = 300

Function Deploy-OVF{
    param($virtualmachine)
    $vm = $virtualmachine
    $vmstatus = Get-VM $vm -ErrorAction 0
    if($vmstatus -ne ""){
        Write-Host "Deploying OVF Template $ovf to Virtual Machine name $vm" -fore Yellow
        Import-VApp -Source $ovf -Name $vm -VMHost $vh -Datastore $ds -DiskStorageFormat $df
    }
    else{
        Write-Host $vm "already exists" -fore Red
    }
}

Function Start-VM{
    param($virtualmachine)
    $vm = Get-VM $virtualmachine -ErrorAction 0
    if($vm.powerstate -ne "PoweredOn"){
        # Start the Virtual Machine
        Write-Host "Starting $vm" -fore Yellow
        $vm | Start-VM -confirm:$false | Out-Null
    }
    else{
        Write-Host $vm "is already powered on" -fore Red
    }
}

Function Set-NetworkInterface{
    param($virtualmachine)
    $vm = Get-VM $virtualmachine -ErrorAction 0
    $dhcp = $dhcp.ToLower()
    $toolsStatus = (Get-VM $vm | Get-View).Guest.ToolsStatus
    if($vm.powerstate -eq "PoweredOn"){
        if($toolsStatus -eq "toolsOk"){
 
            # Create the DNS entries in /etc/resolv.conf if they don't exist
            # TODO: Convert in to loop for array of DNS servers
            if($dns1 -ne ""){
            $script = 'grep #dns1# /etc/resolv.conf 2>&1; if [ $? -ne 0 ]; then echo "nameserver #dns1#" >> /etc/resolv.conf; fi'
            $script = $script.Replace("#dns1#", $dns1)
            Write-Host "Configuring DNS $dns1" -fore Yellow
            $vm | Invoke-VMScript -GuestUser $gu -GuestPassword $gp $script
            }

            # Add IP Address information to eth0
            # TODO: Create array for multiple network interfaces
            $script = 'ETH=/etc/sysconfig/network-scripts/ifcfg-eth0;'
            if($dhcp -eq "false"){
                $script += ' grep ^BOOTPROTO "$ETH" 2>&1; if [ $? -ne 0 ]; then echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-eth0; else sed -i "s/^BOOTPROTO=.*$/BOOTPROTO=none/" "$ETH"; fi;'
                if($ip -ne ""){
                    $script += ' grep ^IPADDR "$ETH" 2>&1; if [ $? -ne 0 ]; then echo "IPADDR=#ip#" >> /etc/sysconfig/network-scripts/ifcfg-eth0; else sed -i "s/^IPADDR=.*$/IPADDR=#ip#/" "$ETH"; fi;'
                    $script = $script.Replace("#ip#", $ip)
                }
                if($nm -ne ""){
                    $script += ' grep ^NETMASK "$ETH" 2>&1; if [ $? -ne 0 ]; then echo "NETMASK=#nm#" >> /etc/sysconfig/network-scripts/ifcfg-eth0; else sed -i "s/^NETMASK=.*$/NETMASK=#nm#/" "$ETH"; fi;'
                }
                if($gw -ne ""){
                    $script += ' grep ^GATEWAY "$ETH" 2>&1; if [ $? -ne 0 ]; then echo "GATEWAY=#gw#" >> /etc/sysconfig/network-scripts/ifcfg-eth0; else sed -i "s/^GATEWAY=.*$/GATEWAY=#gw#/" "$ETH"; fi;'
                }
                if(($ip -ne "") -or ($nm -ne "") -or ($gw -ne "")){
                    Write-Host "Configuring Network Interface for $vm" -fore Yellow
                    $vm | Invoke-VMScript -GuestUser $gu -GuestPassword $gp $script
                }
            }
            else{
                $script += ' grep ^BOOTPROTO "$ETH" 2>&1; if [ $? -ne 0 ]; then echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-eth0; else sed -i "s/^BOOTPROTO=.*$/BOOTPROTO=none/" "$ETH"; fi;'
                Write-Host "Configuring Network Interface for $vm" -fore Yellow
                $vm | Invoke-VMScript -GuestUser $gu -GuestPassword $gp $script
            }
        }
        else{
            Write-Host $vm "VMware Tools are out of date or not running" -fore Red
            }
    }
    else{
        Write-Host $vm "is not running" -fore Red
    }
}

# Connect to ESXi Host
Write-Host "Connecting to ESXi Host..."
Connect-VIServer -Server $vmhost

# Populate list and settings for each VM
$guests = Import-CSV -Path $csvfile

ForEach ($vms in $guests) {
    $vh = $vmhost
    $vm = $vms.VM_Name
    $dhcp = $vms.Boolean_DHCP
    $ip = $vms.Static_IP
    $nm = $vms.Netmask
    $gw = $vms.Default_GW
    $dns1 = $vms.Primary_DNS

  # Ensure VM name is defined
  if ($vm -ne "") {
    Deploy-OVF $vm
    Start-VM $vm
    Set-NetworkInterface $vm
  }
  else {
    Write-Host "Virtual Machine name is not defined." -fore Red
  }
}

Write-Host "All Virtual Machines have been deployed." -fore Green
Write-Host "Disconnecting from ESXi Host..."
Disconnect-VIServer -Confirm:$false
