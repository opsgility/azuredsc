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

  [parameter(Mandatory)]
  $CertificatePath,

  [parameter(Mandatory)]
  $PullServer,

  [parameter(Mandatory)]
  $ConfigurationName,

  [parameter(Mandatory, ParameterSetName="JoinVNET")]
  [switch]$JoinVNET,
  
  [parameter(Mandatory, ParameterSetName="JoinVNET")]
  [parameter(Mandatory, ParameterSetName="JoinDomain")]
  [string]$Subnet,

  [parameter(Mandatory, ParameterSetName="JoinDomain")]
  [switch]$JoinDomain,
  
  [parameter(Mandatory, ParameterSetName="JoinDomain")]
  [string]$DomainFQDN,
  
  [parameter(Mandatory="false", ParameterSetName="JoinDomain")]
  [switch]$DomainOU
  
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

$Credential = Get-Credential 

$ImageName = (Get-AzureVMImage | Where { $_.ImageFamily -eq "Windows Server 2012 R2 Datacenter" } | sort PublishedDate -Descending | Select-Object -First 1).ImageName

# Existing certificate must exist
$pwd = $credential.GetNetworkCredential().password
$pfxName = Join-Path $PSScriptRoot "PSDSCPullServerCert.pfx"
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$cert.Import($pfxName,$pwd,'Exportable')


Write-Host "Creating DSC pull client machine $name in cloud service $ServiceName" -ForegroundColor Green

# Create virtual machine with PSDSCPullServer certificate deployed
$vmConfig = New-AzureVMConfig -Name $Name -ImageName $ImageName -InstanceSize Small  

if($PSCmdlet.ParameterSetName -eq "JoinDomain")
{
   $domain = $DomainFQDN.Split(".")[0]
   $domainCredential = Get-Credential -Message "Enter Credentials to Join Domain"
   if($DomainOU.IsPresent -eq $false)
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
    Write-Host "Deploying Virtual Machine $Name" -ForegroundColor Green
    New-AzureVM -ServiceName $ServiceName -VMs $vmConfig -WaitForBoot
}
else
{
    Write-Host "Deploying Virtual Machine $Name into subnet $Subnet" -ForegroundColor Green
    $vmConfig | Set-AzureSubnet -SubnetName $Subnet
    New-AzureVM -ServiceName $ServiceName -VMs $vmConfig -WaitForBoot
}


Write-Host "Downloading and installing WinRM Certificate for secure communications" -ForegroundColor Green
& $PSScriptRoot\Helper\InstallWinRMCertAzureVM.ps1 -SubscriptionName $SubscriptionName -ServiceName $ServiceName -Name $Name


$DSCLocalConfigScript = Join-Path $PSScriptRoot "\Scripts\PullClientScripts.zip"
$DSCLocaLConfigScriptDestinationPath = "C:\DSCScript" 
$DSClOCALConfigScriptFullPath = Join-Path $DSCLocalConfigScriptDestinationPath "Assert_DSCLocalConfig.ps1"
Write-Host "Uploading DSC Configuration Script to configure DSC Client Machine" -ForegroundColor Green

& $PSScriptRoot\Helper\UploadAndExtractFile.ps1 -SubscriptionName $SubscriptionName -ServiceName $ServiceName -Name $Name -FileUpload $DSCLocalConfigScript -LocalPath $DSCLocalConfigScriptDestinationPath -Credential $Credential

Write-Host "Setting DSC Local Configuration to use Pull Server" -ForegroundColor Green

$uri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $Name 


Invoke-Command -ConnectionUri $uri -Credential $Credential -ArgumentList $DSCLocalConfigScriptFullPath, $PullServer, $ConfigurationName -ScriptBlock {
    param($DSCLocalConfigScriptFullPath, $PullServer, $ConfigurationName)
    Write-Host "Configuring the Pull Server Client using Script $DSCLocalConfigScriptFullPath, Pull Server $PullServer and Configuration $ConfigurationName" -ForegroundColor Green
    & $DSCLocalConfigScriptFullPath $PullServer $ConfigurationName
}
