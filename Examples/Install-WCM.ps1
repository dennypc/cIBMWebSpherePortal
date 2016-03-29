#requires -Version 5

Configuration IBMWCM
{
    param
    (
        [Parameter(Mandatory)]
        [PSCredential]
        $InstallCredential,
        
        [Parameter(Mandatory)]
        [PSCredential]
        $WebSphereAdminCredential
    )
    
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DSCResource -ModuleName 'cIBMInstallationManager' -ModuleVersion '1.0.5'
    Import-DSCResource -ModuleName 'cIBMWebSpherePortal' -ModuleVersion '1.0.1'
    
    node localhost {
        Package SevenZip {
            Ensure = 'Present'
            Name = '7-Zip 9.20 (x64 edition)'
            ProductId = '23170F69-40C1-2702-0920-000001000000'
            Path = 'C:\Media\7z920-x64.msi'
        }
        cIBMInstallationManager IIMInstall
        {
            Ensure = 'Present'
            InstallationDirectory = 'C:\IBM\IIM'
            Version = '1.8.3'
            SourcePath = 'C:\Media\agent.installer.win32.win32.x86_1.8.3000.20150606_0047.zip'
            DependsOn = '[Package]SevenZip'
        }
        cIBMWebSpherePortal WPInstall
        {
            Ensure = 'Present'
            PortalEdition = 'WCM'
            HostName = 'localportal.domain.com'
            Version = '8.5.0.0'
            SourcePath = 'C:\Media\Portal85\'
            WebSphereAdministratorCredential = $WebSphereAdminCredential
            DependsOn = '[cIBMInstallationManager]IIMInstall'
            PsDscRunAsCredential = $InstallCredential
        }
    }
}
$configData = @{
    AllNodes = @(
        @{
            NodeName = "localhost"
            PSDscAllowPlainTextPassword = $true
         }
    )
}
$installCredential = (Get-Credential -UserName "Administrator" -Message "Enter the credentials of a Windows Administrator of the target server")
$wasAdminCredential = (Get-Credential -UserName "wsadmin" -Message "Enter the administrator credentials for the WebSphere Administrator")
IBMWCM -InstallCredential $installCredential -WebSphereAdminCredential $wasAdminCredential
Start-DscConfiguration -Wait -Force -Verbose IBMWCM