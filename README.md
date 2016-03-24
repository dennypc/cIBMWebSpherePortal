#cIBMWebSpherePortal

PowerShell CmdLets and Class-Based DSC resources to manage IBM WebSphere Portal Server on Windows Environments.

To get started using this module just type the command below and the module will be downloaded from [PowerShell Gallery](https://www.powershellgallery.com/packages/cIBMWebSpherePortal/)
```shell
PS> Install-Module -Name cIBMWebSpherePortal
```
**Known Issue:** When I run the underlying install script via normal PowerShell the installation finishes successfully.  However I have not been able to get the installation to work whis executed by DSC (The issue occurs while setting up the WebSphere profile for Portal).  I'm releasing this module because at the very least it helps me validate the Portal installation on a target machine.  My workflow has been to install Portal via the underlying scripts and then use DSC for validation.

**Coming Soon:** _SQL Server-based Database Transfer and Active Directory Configuration CmdLets_ Subscribe to this repo to get notified.

## Resources

* **cIBMWebSpherePortal** installs IBM WebSphere Portal on target machine.

### cIBMWebSpherePortal

* **Ensure**: (Required) Ensures that Portal is Present or Absent on the machine.
* **Version**: (Key) The version of Portal to install
* **PortalEdition**: (Key) The edition of Portal to install.  Options: MP, EXPRESS, WCM, EXTEND
* **HostName**: (Required) The hostname that Portal will use.  If the DNS cannot resolve it, it will need to be added to etc/hosts
* **WebSphereAdministratorCredential**: (Required) Credential for the WebSphere Administrator.
* **PortalAdministratorCredential**: (Optional) Credential for the Portal Administrator.
* **InstallationDirectory**: Installation path.  Default: C:\IBM\WebSphere.
* **Primary**: _Boolean_ Specifies if target machine is the primary.  If so profile will be created, otherwise binary install.
* **CellName**: (Optional) Name of the WebSphere Cell.  Default: wpCell
* **NodeName**: (Optional) Name of the WebSphere Node.  Default: wpNode
* **ServerName**: (Optional) Name of the WebSphere Server.  Default: WebSphere_Portal
* **ProfileName**: (Optional) Name of the WebSphere Profile.  Default: wp_profile
* **IMSharedLocation**: Location of the IBM Installation Manager cache.  Default: C:\IBM\IMShared
* **InstallMediaConfig**: (Optional) Path to the clixml export of the IBMProductMedia object that contains media configuration.
* **ResponseFileTemplate**: (Optional) Path to the response file template to use for the installation.
* **SourcePath**: UNC or local file path to the directory where the IBM installation media resides.
* **SourcePathCredential**: (Optional) Credential to be used to map sourcepath if a remote share is being specified.

_Note_ InstallMediaConfig and ResponseFileTemplate are useful parameters when there's no built-in support for the Portal edition you need to install or when you have special requirements based on how your media is setup or maybe you have unique response file template needs.
If you create your own Response File template it is expected that the template has various variables needed for the installation.  See sample response file template before when planning to roll out your own.

## Depedencies
* [cIBMWebSphereAppServer](http://github.com/dennypc/cIBMWebSphereAppServer) DSC Resource/CmdLets for IBM WebSphere App Server
* [cIBMInstallationManager](http://github.com/dennypc/cIBMInstallationManager) DSC Resource/CmdLets for IBM Installation Manager
* [7-Zip](http://www.7-zip.org/ "7-Zip") needs to be installed on the target machine.  You can add 7-Zip to your DSC configuration by using the Package
DSC Resource or by leveraging the [x7Zip DSC Module](https://www.powershellgallery.com/packages/x7Zip/ "x7Zip at PowerShell Gallery")

## Versions

### 1.0.1
* Supports binary install via new Primary DSC property. 
* Supports installing on top of existing App Servers.  Module automatically checks if WebSphere is installed.

### 1.0.0

* Initial release with the following resources 
    - cIBMWebSpherePortal

## Testing

The table below outlines the tests that various Portal editions/versions have been verify to date.  As more configurations are tested there should be a corresponding entry for Media Configs and Response File Templates.  Could use help on this, pull requests welcome :-)

| Portal Version | Operating System               | MP | WCM | EXPRESS | EXTEND |
|----------------|--------------------------------|----|-----|---------|--------|
| v8.5           |                                |    |     |         |        |
|                | Windows 2012 R2 (64bit)        |    |  x  |         |        |
|                | Windows 10 (64bit)             |    |     |         |        |
|                | Windows 2008 R2 Server (64bit) |    |     |         |        |

## Media Files

The installation depents on media files that have already been downloaded.  In order to get the media files please check your IBM Passport Advantage site.

The table below shows the currently supported (i.e. tested) media files.

| WAS Version | WAS Edition | Media Files           |
|-------------|-------------|-----------------------|
| v8.5        |             |                       |
|             | WCM         | WSP_Server_8.5_Setup.zip |
|             |             | WSP_Server_8.5_Install.zip |
|             |             | WSA_Server_NetDeplo_8.5.5.2.zip |
|             |             | WS_SDK_JAVA_TECH_7.0.6.1.zip |
|             |             | WCM_8.5_SETUP.zip |
|             |             | WCM_8.5_Install.zip |

## Examples

### Install IBM WebSphere Portal - WCM Edition

This configuration will install [7-Zip](http://www.7-zip.org/ "7-Zip") using the DSC Package Resource, install/update IBM Installation Manager
and finally install IBM WCM

Note: This requires the additional DSC modules:
* xPsDesiredStateConfiguration
* cIBMInstallationManager

Note: _You should NOT use PSDscAllowPlainTextPassword (unless is for testing).  See this article on how to properly secure MOF files:_ https://msdn.microsoft.com/en-us/powershell/dsc/secureMOF

Note: _See Known Issue section above_

```powershell
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
    Import-DSCResource -ModuleName 'cIBMInstallationManager'
    Import-DSCResource -ModuleName 'cIBMWebSpherePortal'
    
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
```