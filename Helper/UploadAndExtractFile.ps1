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
 [Parameter(Mandatory)]
 [string]$SubscriptionName,
 [Parameter(Mandatory)]
 [string]$ServiceName,
 [Parameter(Mandatory)]
 [string]$Name,
 [Parameter(Mandatory)]
 [string]$FileUpload,
 [Parameter(Mandatory)]
 [string]$LocalPath,
 [Parameter(Mandatory)]
 [pscredential]$Credential
)

Set-StrictMode -Version Latest

Select-AzureSubscription $SubscriptionName

$fileName = Split-Path -Path $FileUpload -Leaf

$zipfileBytes = gc -Encoding byte $FileUpload

Write-Host "Getting Remote PowerShell Endpoint" -ForegroundColor Green
$uri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $Name


Invoke-Command -ConnectionUri $uri -Credential $Credential -ArgumentList $zipfileBytes, $LocalPath, $fileName  -ScriptBlock {
    param([byte[]]$zipfileBytes, $localPath, $fileName)
 
    function CreateFolderIfNotExist($path)
    {
	    if((Test-Path $path) -eq $false)
	    {
   		    New-Item -ItemType directory -Path $path -Force | Out-Null
	    }
    }
    function UnzipFileTo($sourcepath, $destinationpath)
    {
	    CreateFolderIfNotExist $destinationpath
	    $shell_app = new-object -com shell.application
	    $zip_file = $shell_app.namespace($sourcepath)
	    $destination = $shell_app.namespace($destinationpath)
	    $destination.Copyhere($zip_file.items(), 16)
    }
 
    # Temporary path to download file to 
    $tmpDownloadPath = Join-Path $env:TEMP $fileName

    Write-Host "Copying file to $tmpDownloadPath" -ForegroundColor Green
    $zipfileBytes | Set-Content $tmpDownloadPath -Force -Encoding byte

    Write-Host "Unzipping file from $tmpDownloadPath to $localPath"
    UnzipFileTo -sourcepath $tmpDownloadPath -destinationpath $localPath

    Write-Host "Deleting Temp File $tmpDownloadPath" -ForegroundColor Green
    
}