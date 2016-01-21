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

# Default variables
$vmHost = "192.168.0.20"
$vmDatastore = "datastore2"
$vmDiskFormat = "Thin"
$vmCsvFile = "D:\test.csv"
$vmOvf = "D:\vm_images\centos5\centos5.ovf"
$vmGuestLogin = "root"
$vmGuestPassword = "password1234"

# VM Startup timeout in seconds
$maxTimeOut = 300

# Connect to ESXi Host
Write-Host "Connecting to ESXi Host..."
Connect-VIServer -Server $vmHost

# Populate list and settings for each VM
$vmList = Import-CSV -Path $vmCsvFile

ForEach ($vm in $vmList) {

  # Ensure VM name is defined
  if ($vm.VM_Name -ne "") {

    # Verify if VM already exists
    $noVM = Get-VM -Name $vm.VM_Name -ErrorAction 0
    if (!($noVM)) {

      # Begin VM import process
      Write-Host "Deploying $($vm.VM_Name)..."
      Import-VApp -Source $vmOvf -Name $vm.VM_Name -VMHost $vmHost -Datastore $vmDatastore -DiskStorageFormat $vmDiskFormat

      # Start up the VM and wait for VMware Guest Tools to start
      Write-Host "Starting $($vm.VM_Name)..."
      Start-VM -VM $vm.VM_Name -confirm:$false | Out-Null
      $timeOut = New-Timespan -Seconds $maxTimeOut
      $loops = 0
      Do {
        Start-Sleep -Seconds 10
        $vmStatus = (Get-VM -Name $vm.VM_Name).ExtensionData.Guest.ToolsStatus
      } Until (($vmStatus -match 'toolsOk') -Or ($loops -gt $maxTimeOut))

      # Need to allow the services to start up
      Write-Host "$($vm.VM_Name) is now started. Waiting for services to come up."
      Start-Sleep -Seconds 30

      # Set up network configuration on system
      $script = 'echo "DHCP=#DHCP#";echo "IP=#IP#"; echo "NM=#NM#"; echo "GW=#GW#"; echo "DNS1=#DNS1#"; DHCP=#DHCP#; if [ "$DHCP" = "false" ]; then echo "IPADDR=#IP#" >> /etc/sysconfig/network-scripts/ifcfg-eth0; echo "NETMASK=#NM#" >> /etc/sysconfig/network-scripts/ifcfg-eth0; echo "GATEWAY=#GW#" >> /etc/sysconfig/network-scripts/ifcfg-eth0; sed -i "s/^BOOTPROTO=.*$/BOOTPROTO=static/" /etc/sysconfig/network-scripts/ifcfg-eth0; echo "" > /etc/resolv.conf; echo "nameserver #DNS1#" >> /etc/resolv.conf; else sed -i "s/^BOOTPROTO=.*$/BOOTPROTO=dhcp/" /etc/sysconfig/network-scripts/ifcfg-eth0; fi; /sbin/ifdown eth0; /sbin/ifup eth0;'

      $script = $script.Replace("#DHCP#", $vm.Boolean_DHCP).Replace("#IP#", $vm.Static_IP).Replace("#NM#", $vm.Netmask)
      $script = $script.Replace("#GW#", $vm.Default_GW).Replace("#DNS1#", $vm.Primary_DNS)
      Write-Host "Setting up Virtual Machine network settings."
      $provision = Invoke-VMScript -VM $vm.VM_Name -GuestUser $vmGuestLogin -GuestPassword $vmGuestPassword -ScriptType Bash -ScriptText $script
      $provision.ScriptOutput

    }
    else {
      Write-Host "Virtual Machine already exists. Nothing to do." -ForegroundColor Yellow
    }
  }
  else {
    Write-Host "Virtual Machine name is not defined." -ForegroundColor Red
  }
}

Write-Host "All Virtual Machines have been deployed." -ForegroundColor Green
Write-Host "Disconnecting from ESXi Host..."
Disconnect-VIServer -Confirm:$false
