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

Set-StrictMode -Version Latest

# Get certificate previously deployed during provisioning 
$psDscCert = Get-ChildItem CERT:\LocalMachine\MY\ | where {$_.Subject -eq "CN=PSDSCPullServerCert"}


Configuration Assert_DSCService
{
    param(
    [parameter(Mandatory)]
    [string]$certificateThumbPrint
    )

    Import-DSCResource -ModuleName DSCService

    Node localhost
    {
        WindowsFeature DSCServiceFeature
        {
            Ensure = "Present"
            Name = "DSC-Service"            
        }

        DSCService PSDSCPullServer
        {
            Ensure                  = "Present"
            Name                    = "PSDSCPullServer"
            Port                    = 8080
            PhysicalPath            = "$env:SystemDrive\inetpub\wwwroot\PSDSCPullServer"       
            EnableFirewallException = $true     
            CertificateThumbPrint   = $certificateThumbPrint         
            ModulePath              = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Modules"
            ConfigurationPath       = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Configuration"            
            State                   = "Started"
            DependsOn               = "[WindowsFeature]DSCServiceFeature"                        
        }

        DSCService PSDSCComplianceServer
        {
            Ensure                  = "Present"
            Name                    = "PSDSCComplianceServer"
            Port                    = 9080
            PhysicalPath            = "$env:SystemDrive\inetpub\wwwroot\PSDSCComplianceServer"
            EnableFirewallException = $true     
            CertificateThumbPrint   = "AllowUnencryptedTraffic"
            State                   = "Started"
            IsComplianceServer      = $true
            DependsOn               = "[WindowsFeature]DSCServiceFeature"
        }

    }
}

Assert_DSCService -certificateThumbPrint $psDscCert.Thumbprint 
Start-DscConfiguration -Path Assert_DSCService -Wait -Verbose -Force
