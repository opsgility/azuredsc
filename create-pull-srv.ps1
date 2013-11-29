<#
 Copyright (c) Opsgility.  All rights reserved.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
   http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
#>

<#
  .SYNOPSIS
  This Cmdlet creates a virtual machine and bootstraps a DSC Pull Server

  .DESCRIPTION
  This Cmdlet creates a virtual machine and bootstraps a DSC Pull Server.
  
  .EXAMPLE

  # No VNET
  .\create-pull-srv.ps1 -SubscriptionName opsgilitytraining -ServiceName pullsvc -Name pullsrv -Size Small -Location "West US" 

  # Create domain joined
  .\create-pull-srv.ps1 -SubscriptionName opsgilitytraining -ServiceName pullsvc -Name pullsrv -Size Small -JoinDomain -AffinityGroup "MYAG" -VNET "MYVNET" -Subnet "MYSUBNET" -DomainFQDN "mydomain.com"
#>

[CmdletBinding(DefaultParameterSetName="default")]
param(
  [parameter(Mandatory)]
  [string]$SubscriptionName,
  
  [parameter(Mandatory)]
  [string]$ServiceName, 
  
  [parameter(Mandatory)]
  [string]$Name,
  
  [parameter(Mandatory)]
  [string]$Size,

  [parameter(Mandatory, ParameterSetName="default")]
  [string]$Location,

  [parameter(Mandatory, ParameterSetName="JoinDomain")]
  [switch]$JoinDomain,
  
  [parameter(Mandatory, ParameterSetName="JoinDomain")]
  [string]$AffinityGroup,
  
  [parameter(Mandatory, ParameterSetName="JoinDomain")]
  [string]$VNET,

  [parameter(Mandatory, ParameterSetName="JoinDomain")]
  [string]$Subnet,
  
  [parameter(Mandatory, ParameterSetName="JoinDomain")]
  [string]$DomainFQDN,
  
  [parameter(ParameterSetName="JoinDomain")]
  [String]$DomainOU
)

Set-StrictMode -Version Latest

function IsAdmin
{
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()` 
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") 
    
    return $IsAdmin
}


if((IsAdmin) -eq $false)
{
	Write-Error "This script generates certificates and installs them in the local machine container and must be elevated to run."
	return
}

# Automate creation of self signed certs
# Downloadable from http://gallery.technet.microsoft.com/scriptcenter/Self-signed-certificate-5920a7c6#content
. Helper\New-SelfSignedCertificateEx.ps1

$Credential = Get-Credential -Message "Enter local admin credentials" 

$ImageName = (Get-AzureVMImage | Where { $_.ImageFamily -eq "Windows Server 2012 R2 Datacenter" } | sort PublishedDate -Descending | Select-Object -First 1).ImageName

Write-Host "Creating Self-Signed Certficate for VM $name" -ForegroundColor Green
$pwd = $credential.GetNetworkCredential().password
$pfxName = Join-Path $PSScriptRoot "PSDSCPullServerCert.pfx"

New-SelfsignedCertificateEx -Subject "CN=PSDSCPullServerCert" -EKU "Server Authentication", "Client authentication" `
                            -KeyUsage "KeyEncipherment", "DigitalSignature" -SAN $Name `
                            -AllowSMIME -Path $pfxName -Password (ConvertTo-SecureString $pwd -AsPlainText -Force) -Exportable 

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$cert.Import($pfxName,$pwd,'Exportable')

Write-Host "Creating pull server $name in cloud service $ServiceName" -ForegroundColor Green

# Create virtual machine with PSDSCPullServer certificate deployed
$vmConfig = New-AzureVMConfig -Name $Name -ImageName $ImageName -InstanceSize Small  

if($PSCmdlet.ParameterSetName -eq "JoinDomain")
{
   $domain = $DomainFQDN.Split(".")[0]
   $domainCredential = Get-Credential -Message "Enter Domain User Name and Password to Join Domain $domain"
   if($DomainOU -eq $null -or $DomainOU.Length -eq 0)
   {
      $vmConfig | Add-AzureProvisioningConfig -WindowsDomain -AdminUsername $Credential.UserName -Password $credential.GetNetworkCredential().password -EnableWinRMHttp -X509Certificates $cert -JoinDomain $DomainFQDN -Domain $Domain -DomainUserName $domainCredential.UserName -DomainPassword $domainCredential.GetNetworkCredential().password
   }
   else
   {
      $vmConfig | Add-AzureProvisioningConfig -WindowsDomain -AdminUsername $Credential.UserName -Password $credential.GetNetworkCredential().password -EnableWinRMHttp -X509Certificates $cert -JoinDomain $DomainFQDN -Domain $Domain -DomainUserName $domainCredential.UserName -DomainPassword $domainCredential.GetNetworkCredential().password -MachineObjectOU $DomainOU
   }
}
else
{
   $vmConfig | Add-AzureProvisioningConfig -Windows -AdminUsername $Credential.UserName -Password $credential.GetNetworkCredential().password -EnableWinRMHttp -X509Certificates $cert 
}

if($PSCmdlet.ParameterSetName -eq "default")
{
    Write-Host "Deploying Virtual Machine in $Location" -ForegroundColor Green
    New-AzureVM -ServiceName $ServiceName -Location $Location -VMs $vmConfig -WaitForBoot 
}
else
{
    Write-Host "Deploying Virtual Machine in AffinityGroup: $AffinityGroup and Virtual Network: $VNET" -ForegroundColor Green
    $vmConfig | Set-AzureSubnet -SubnetName $Subnet
    New-AzureVM -ServiceName $ServiceName -AffinityGroup $AffinityGroup -VNetName $VNET -VMs $vmConfig -WaitForBoot 
}

Write-Host "Downloading and installing WinRM Certificate for secure communications" -ForegroundColor Green
& $PSScriptRoot\Helper\InstallWinRMCertAzureVM.ps1 -SubscriptionName $SubscriptionName -ServiceName $ServiceName -Name $Name


Write-Host "Uploading and extracting DSC Resource Provider" -ForegroundColor Green
$DSCProviderPath = Join-Path $PSScriptRoot "\Scripts\Demo_DSCService.zip"
$DSCProviderDestinationPath = "C:\Program Files\WindowsPowerShell\Modules\DSCService"

& $PSScriptRoot\Helper\UploadAndExtractFile.ps1 -SubscriptionName $SubscriptionName -ServiceName $ServiceName -Name $Name -FileUpload $DSCProviderPath -LocalPath $DSCProviderDestinationPath -Credential $Credential



$DSCProviderConfigScript = Join-Path $PSScriptRoot "\Scripts\PullServerScripts.zip"
$DSCProviderConfigScriptDestinationPath = "C:\DSCScript" 
$DSCProviderConfigScriptFullPath = Join-Path $DSCProviderConfigScriptDestinationPath "Assert_DSCService.ps1"
Write-Host "Uploading DSC Configuration Script to configure DSC Pull Server" -ForegroundColor Green

& $PSScriptRoot\Helper\UploadAndExtractFile.ps1 -SubscriptionName $SubscriptionName -ServiceName $ServiceName -Name $Name -FileUpload $DSCProviderConfigScript -LocalPath $DSCProviderConfigScriptDestinationPath -Credential $Credential



Write-Host "Installing DSC Resource Service and configuring REST endpoints" -ForegroundColor Green

$uri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $Name 
Invoke-Command -ConnectionUri $uri -Credential $Credential -ArgumentList $DSCProviderConfigScriptFullPath -ScriptBlock {
    param($DSCProviderConfigScriptFullPath)
    Write-Host "Configuring the Pull Server using Script $DSCProviderConfigScriptFullPath" -ForegroundColor Green
    
    & $DSCProviderConfigScriptFullPath 
}
