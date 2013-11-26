
. $PSScriptRoot\SetConfiguration.ps1



Configuration WebServer {
    param($node)
    node $node
    {
        WindowsFeature IIS
        {
            Ensure = "Present"
            Name = "Web-Server"
            IncludeAllSubFeature = $true
        }
    }
}


SetConfiguration -Configuration WebServer
