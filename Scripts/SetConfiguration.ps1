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

# Get certificate previously deployed during provisioning 
$psDscCert = Get-ChildItem CERT:\LocalMachine\MY\ | where {$_.Subject -eq "CN=PSDSCPullServerCert"}



# Creates a deterministic GUID based on a name (configuration name, computer name etc..)
function GetIDForName($name)
{
    $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $utf8 = new-object -TypeName System.Text.UTF8Encoding
    [byte[]]$hash = $md5.ComputeHash($utf8.GetBytes($name.ToLower()))
    $configurationId = New-Object System.Guid -ArgumentList (,$hash)
    return $configurationId
}


Function SetConfiguration
{
    param(
      $Configuration
    )

    $stagingPath = "C:\Program Files\WindowsPowerShell\DscService\Configuration"


    $configurationId = GetIDForName -name $Configuration

    Write-Host "Saving Configuration $Configuration with ID $configurationId in $stagingPath " -ForegroundColor Green

    # Enable saving encrypted password to file 
    $Global:AllNodes =
    @{
        AllNodes = @( 
            @{  
                NodeName      = "$configurationId"
                CertificateID = $psDscCert.Thumbprint
            }
        )
    }

    Write-Host "Specifying cert for decryption:" $psDscCert.Thumbprint

    # Execute the configuration for the node 
    $output = (& $Configuration -node $configurationId -outputpath $stagingPath -ConfigurationData $Global:AllNodes)

    $mofPath =  (Join-Path $stagingPath "$configurationId.mof")
    $mofCheckSumPath = (Join-Path $stagingPath "$configurationId.mof.checksum")

    New-DSCCheckSum -ConfigurationPath $mofPath -OutPath $mofCheckSumPath

    Write-Host "Saved checksum for file $mofCheckSumPath" -ForegroundColor Green


}