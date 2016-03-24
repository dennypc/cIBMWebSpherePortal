# Import IBM WebSphere App Server Utils Module
Import-Module $PSScriptRoot\cIBMWebSpherePortalUtils.psm1 -ErrorAction Stop

enum Ensure {
    Absent
    Present
}

enum WASEdition {
    Base
    ND
    Express
    Developer
    Liberty
}

enum PortalEdition {
    MP
    EXPRESS
    WCM
    EXTEND
}

<#
   DSC resource to manage the installation of IBM WebSphere Portal.
   Key features: 
    - Install IBM WebSphere Portal Server for the first time
    - Can use media on the local drive as well as from a network share which may require specifying credentials
#>

[DscResource()]
class cIBMWebSpherePortal {
    [DscProperty(Mandatory)]
    [Ensure] $Ensure
    
    [DscProperty(Key)]
    [PortalEdition] $PortalEdition
    
    [DscProperty(Key)]
    [String] $Version
    
    [DscProperty(Mandatory)]
    [String] $HostName
    
    [DscProperty()]
    [String] $InstallationDirectory = "C:\IBM\WebSphere"
    
    [DscProperty(Mandatory)]
    [System.Management.Automation.PSCredential] $WebSphereAdministratorCredential
    
    [DscProperty()]
    [System.Management.Automation.PSCredential] $PortalAdministratorCredential

    [DscProperty()]
    [String] $CellName = "wpCell"
    
    [DscProperty()]
    [String] $NodeName = "wpNode"
    
    [DscProperty()]
    [String[]] $ServerName = "WebSphere_Portal"
    
    [DscProperty()]
    [String] $ProfileName = "wp_profile"
    
    [DscProperty()]
    [String] $IMSharedLocation = "C:\IBM\IMShared"
    
    [DscProperty()]
    [String] $InstallMediaConfig
    
    [DscProperty()]
    [String] $ResponseFileTemplate
    
    [DscProperty()]
    [Bool] $Primary = $true

    [DscProperty()]
    [String] $SourcePath
    
    [DscProperty()]
    [System.Management.Automation.PSCredential] $SourcePathCredential

    <#
        Installs IBM WebSphere Portal
    #>
    [void] Set () {
        try {
            if ($this.Ensure -eq [Ensure]::Present) {
                Write-Verbose -Message "Starting installation of IBM WebSphere Portal"
                $sevenZipExe = Get-SevenZipExecutable
                if (!([string]::IsNullOrEmpty($sevenZipExe)) -and (Test-Path($sevenZipExe))) {
                    $ibmwpEdition = $this.PortalEdition.ToString()
                    $wpVersion = $this.Version
                    $tempServerName = $this.ServerName[0]
                    $mediaConfig = $null
                    $responseFile = $null
                    
                    $WASInsDir = Get-IBMWebSphereAppServerInstallLocation -WASEdition ND
                    $wasndInstalled = ($WASInsDir -and (Test-Path $WASInsDir))
                    if (!($this.InstallMediaConfig)) {
                        if ($wasndInstalled) {
                            $mediaConfig = Join-Path -Path $PSScriptRoot -ChildPath "InstallMediaConfig\$ibmwpEdition-$wpVersion.xml"
                        } else {
                            $mediaConfig = Join-Path -Path $PSScriptRoot -ChildPath "InstallMediaConfig\$ibmwpEdition-$wpVersion-plus-ND.xml"
                        }
                    }
                    if (!($this.ResponseFileTemplate)) {
                        if ($wasndInstalled -and $this.Primary) {
                            $responseFile = Join-Path -Path $PSScriptRoot -ChildPath "ResponseFileTemplates\$ibmwpEdition-$wpVersion-template.xml"
                        } elseif ($wasndInstalled) {
                            $responseFile = Join-Path -Path $PSScriptRoot -ChildPath "ResponseFileTemplates\$ibmwpEdition-$wpVersion-template-binary.xml"
                        } elseif ($this.Primary) {
                            $responseFile = Join-Path -Path $PSScriptRoot -ChildPath "ResponseFileTemplates\$ibmwpEdition-$wpVersion-template-plus-ND-binary.xml"
                        } else {
                            $responseFile = Join-Path -Path $PSScriptRoot -ChildPath "ResponseFileTemplates\$ibmwpEdition-$wpVersion-template-plus-ND.xml"
                        }
                    }
                    
                    # Install Portal Only
                    $installed = Install-IBMWebSpherePortal -InstallMediaConfig $mediaConfig -ResponseFileTemplate $responseFile `
                                -InstallationDirectory $this.InstallationDirectory -IMSharedLocation $this.IMSharedLocation -CellName $this.CellName `
                                -ProfileName $this.ProfileName -NodeName $this.NodeName -ServerName $tempServerName -HostName $this.HostName `
                                -WebSphereAdministratorCredential $this.WebSphereAdministratorCredential -PortalAdministratorCredential $this.PortalAdministratorCredential `
                                -SourcePath $this.SourcePath -SourcePathCredential $this.SourcePathCredential
                    
                    if ($installed) {
                        Write-Verbose "IBM WebSphere Portal Installed Successfully"
                    } else {
                        Write-Error "Unable to install IBM WebSphere Portal, please check installation logs for more information"
                    }
                } else {
                    Write-Error "IBM WebSphere Portal installation depends on 7-Zip, please ensure 7-Zip is installed first"
                }
            } else {
                Write-Verbose "Uninstalling IBM WebSphere Portal (Not Yet Implemented)"
            }
        } catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }

    <#
        Performs test to check if Portal is in the desired state, includes 
        validation of installation directory, version, and products installed
    #>
    [bool] Test () {
        Write-Verbose "Checking the IBM WebSphere Portal installation"
        $wpConfiguredCorrectly = $false
        $wpRsrc = $this.Get()
        
        if (($wpRsrc.Ensure -eq $this.Ensure) -and ($wpRsrc.Ensure -eq [Ensure]::Present)) {
            if ($wpRsrc.Version -eq $this.Version) {
                if (((Get-Item($wpRsrc.InstallationDirectory)).Name -eq 
                    (Get-Item($this.InstallationDirectory)).Name) -and (
                    (Get-Item($wpRsrc.InstallationDirectory)).Parent.FullName -eq 
                    (Get-Item($this.InstallationDirectory)).Parent.FullName)) {
                    if ($wpRsrc.PortalEdition -eq $this.PortalEdition) {
                        if (($wpRsrc.ProfileName -eq $this.ProfileName) -and 
                            ($wpRsrc.CellName -eq $this.CellName) -and
                            ($wpRsrc.NodeName -eq $this.NodeName)) {
                            if ((Compare-Object $wpRsrc.ServerName $this.ServerName | where {$_.SideIndicator -eq "=>"}).InputObject.Count -eq 0) {
                                Write-Verbose "IBM WebSphere Portal is installed and configured correctly"
                                $wpConfiguredCorrectly = $true
                            }
                        }
                    }
                }
            }
        } elseif (($wpRsrc.Ensure -eq $this.Ensure) -and ($wpRsrc.Ensure -eq [Ensure]::Absent)) {
            $wpConfiguredCorrectly = $true
        }

        if (!($wpConfiguredCorrectly)) {
            Write-Verbose "IBM WebSphere Portal not configured correctly"
        }
        
        return $wpConfiguredCorrectly
    }

    <#
        Retrieves the current state of Portal
    #>
    [cIBMWebSpherePortal] Get () {
        $RetEnsure = [Ensure]::Absent
        $RetVersion = $null
        $RetWPEdition = $null
        $RetInsDir = $null
        $RetProfileName = $null
        $RetCellName = $null
        $RetNodeName = $null
        $RetServerName = $null

        # Check if WAS ND is installed / Portal depends on it
        $WASInsDir = Get-IBMWebSphereAppServerInstallLocation -WASEdition ND
        
        if($WASInsDir -and (Test-Path($WASInsDir))) {
            Write-Verbose "IBM WAS ND is Present"
            # Attempt to retrieve the Portal version information
            $portalDir = Join-Path -Path (Split-Path $WASInsDir) -ChildPath "PortalServer"
            if ($portalDir -and (Test-Path $portalDir)) {
                $wpVersionInfo = Get-IBMWebSpherePortalVersionInfo ($this.InstallationDirectory) -ErrorAction Continue
                if ($wpVersionInfo -and $wpVersionInfo["Product Directory"]) {
                    Write-Verbose "IBM WebSphere Portal is Present"
                    $portalHome = $wpVersionInfo["Product Directory"]
                    $RetEnsure = [Ensure]::Present
                    if ($portalHome -and ((Split-Path $portalHome) -eq $this.InstallationDirectory)) {
                        $RetInsDir = $this.InstallationDirectory
                        $wpEdition = $this.PortalEdition.ToString()
                        # Ensure that it is the right Portal Edition (i.e. WCM vs EXPRESS vs MP)
                        if ($wpVersionInfo.Products[$wpEdition]) {
                            $RetWPEdition = $this.PortalEdition
                            $RetVersion = $wpVersionInfo.Products[$wpEdition].Version
                        } elseif ($wpVersionInfo.Products.Keys.Count -gt 0) {
                            ForEach ($wpProduct in $wpVersionInfo.Products.Keys) {
                                if (!((@('MP','CFGFW')).Contains($wpProduct))) {
                                    $RetWPEdition = $wpProduct
                                    $RetVersion = $wpVersionInfo.Products.$wpProduct.Version
                                    break;
                                }
                            }
                            if (!($RetWPEdition)) {
                                $RetWPEdition = [PortalEdition]::MP
                                $RetVersion = $wpVersionInfo.Products.MP.Version
                            }
                        }
                    } elseif ($portalHome) {
                        $RetInsDir = (Split-Path $portalHome)
                    }
                    # Retreive the current topology, if it doesn't match return the current topology
                    $wpProfilePath = Join-Path -Path ($this.InstallationDirectory) -ChildPath ($this.ProfileName)
                    if (Test-WebSphereTopology $wpProfilePath $this.CellName $this.NodeName $this.ServerName) {
                        $RetProfileName = $this.ProfileName
                        $RetCellName = $this.CellName
                        $RetNodeName = $this.NodeName
                        $RetServerName = $this.ServerName
                    } else {
                        $wasTopology = Get-WebSphereTopology $wpProfilePath
                        # Return the first node / set of servers found
                        if ($wasTopology -and ($wasTopology.Count -gt 0)) {
                            $RetProfileName = $this.ProfileName
                            ForEach ($wasCell in $wasTopology.Keys) {
                                if ($wasTopology.$wasCell.Count -gt 0) {
                                    ForEach ($wasNode in $wasTopology.$wasCell.Keys) {
                                        if ($wasTopology.$wasCell.$wasNode) {
                                            $RetCellName = $wasCell
                                            $RetNodeName = $wasNode
                                            $RetServerName = $wasTopology.$wasCell.$wasNode
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Write-Verbose "Unable to retrieve the Portal version, Portal is NOT present"
                }
            }
        } else {
            Write-Verbose "IBM WAS ND is NOT Present"
        }

        $returnValue = @{
            Ensure = $RetEnsure
            InstallationDirectory = $RetInsDir
            Version = $RetVersion
            ProfileName = $RetProfileName
            CellName = $RetCellName
            NodeName = $RetNodeName
            ServerName = $RetServerName
        }
        if ($RetWPEdition -ne $null) {
            $returnValue.Add('PortalEdition', $RetWPEdition)
        }

        return $returnValue
    }
}