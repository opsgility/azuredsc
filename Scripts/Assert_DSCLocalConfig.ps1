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

param(
  [parameter(Mandatory)]
  $PullServer,
  [parameter(Mandatory)]
  $Configuration
)

Set-StrictMode -Version Latest

$stagingPath = "C:\Program Files\WindowsPowerShell\DscService\Configuration"

# Creates a deterministic GUID based on a name (configuration name, computer name etc..)
function GetIDForName($name)
{
    $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $utf8 = new-object -TypeName System.Text.UTF8Encoding
    [byte[]]$hash = $md5.ComputeHash($utf8.GetBytes($name.ToLower()))
    $configurationId = New-Object System.Guid -ArgumentList (,$hash)
    return $configurationId
}


Configuration ConfigurePullServer
{
    param ($Node, $Configuration, $PullServer, $certificateThumbPrint)    
    node $Node
    {
        LocalConfigurationManager
        {
            AllowModuleOverwrite = 'True'
            ConfigurationID = $Configuration
            CertificateID = $certificateThumbPrint
            ConfigurationModeFrequencyMins = 15 
            RefreshFrequencyMins = 15
            ConfigurationMode = 'ApplyAndAutoCorrect'
            RebootNodeIfNeeded = 'True'
            RefreshMode = 'PULL' 
            DownloadManagerName = 'WebDownloadManager'
            DownloadManagerCustomData = (@{ServerUrl = $PullServer; CertificateID = $certificateThumbPrint})
        }
    }
}

$pullServerUrl =  "https://" + $PullServer + ":8080/PSDSCPullServer/PSDSCPullServer.svc"
$node = $ENV:COMPUTERNAME

$configurationId = GetIDForName -name $configuration
Write-Host "Configuring Client $node with configuration id $configurationId" -ForegroundColor Green

# Get certificate previously deployed during provisioning 
Write-Host "Adding Certificate to Root Authority to enable SSL"
$psDscCert = Get-ChildItem CERT:\LocalMachine\MY\ | where {$_.Subject -eq "CN=PSDSCPullServerCert"}
$store = get-item Cert:\LocalMachine\Root 
$store.Open("ReadWrite") 
$store.Add($psDscCert) 
$store.Close() 

ConfigurePullServer -Node $node -Configuration $configurationId.Guid  -PullServer $pullServerUrl -certificateThumbPrint $psDscCert.Thumbprint
Set-DscLocalConfigurationManager ConfigurePullServer -ComputerName $node 


