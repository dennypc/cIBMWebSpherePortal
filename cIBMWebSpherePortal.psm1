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

enum PortalConfig {
    Edition
    PortalHome
    ProfileName
    ProfilePath
    ProfileConfigEnginePath
    Version
    CFLevel
    ConfigWizardProfilePath
}

enum DatabaseType {
    SQLSERVER
    DB2
    ORACLE
    DERBY
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
                $wpVersionInfo = Get-IBMWebSpherePortalVersionInfo -ErrorAction Continue
                if ($wpVersionInfo -and $wpVersionInfo["Product Directory"]) {
                    Write-Verbose "IBM WebSphere Portal is Present"
                    $portalHome = $wpVersionInfo["Product Directory"]
                    $RetEnsure = [Ensure]::Present
                    if ($portalHome) {
                        $portalInstDir = (Split-Path $portalHome)
                        if (((Get-Item($portalInstDir)).Name -eq 
                            (Get-Item($this.InstallationDirectory)).Name) -and (
                            (Get-Item($portalInstDir)).Parent.FullName -eq 
                            (Get-Item($this.InstallationDirectory)).Parent.FullName)) {
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
                        } else {
                            $RetInsDir = (Split-Path $portalHome)
                        }
                    }
                    # Retreive the current topology, if it doesn't match return the current topology
                    $wpProfilePath = Join-Path -Path ($this.InstallationDirectory) -ChildPath ($this.ProfileName)
                    if (Test-IBMWebSphereTopology $wpProfilePath $this.CellName $this.NodeName $this.ServerName) {
                        $RetProfileName = $this.ProfileName
                        $RetCellName = $this.CellName
                        $RetNodeName = $this.NodeName
                        $RetServerName = $this.ServerName
                    } else {
                        $wasTopology = Get-IBMWebSphereTopology $wpProfilePath
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

[DscResource()]
class cIBMWebSpherePortalCumulativeFix {
    [DscProperty(Mandatory)]
    [Ensure] $Ensure
    
    [DscProperty(Mandatory)]
    [PortalEdition] $PortalEdition
    
    [DscProperty(Key)]
    [String] $Version
    
    [DscProperty(Key)]
    [int] $CFLevel
    
    [DscProperty()]
    [string] $ProfileName = "wp_profile"
    
    [DscProperty()]
    [bool] $DevMode
    
    [DscProperty(NotConfigurable)]
    [String] $InstallationDirectory
    
    [DscProperty(Mandatory)]
    [PSCredential] $WebSphereAdministratorCredential
    
    [DscProperty()]
    [PSCredential] $PortalAdministratorCredential
    
    [DscProperty()]
    [String[]] $SourcePath
    
    [DscProperty()]
    [System.Management.Automation.PSCredential] $SourcePathCredential
    
    [DscProperty()]
    [PSCredential] $SetupCredential
    
    # Sets the desired state of the resource.
    [void] Set() {
        try {
            if ($this.Ensure -eq [Ensure]::Present) {
                $cfLevelStr = $this.CFLevel
                $WASInsDir = Get-IBMWebSphereAppServerInstallLocation -WASEdition ND
                $portalDir = Join-Path -Path (Split-Path $WASInsDir) -ChildPath "PortalServer"
                $profilePath = Join-Path -Path (Split-Path $WASInsDir) -ChildPath $this.ProfileName
                
                if ((Test-Path $portalDir) -and (Test-Path $profilePath)) {
                    Write-Verbose "Starting installation of IBM WebSphere Portal Cumulative Fix: $cfLevelStr"
                    
                    $updated = Install-IBMWebSpherePortalCumulativeFix `
                            -CFLevel $this.CFLevel `
                            -DevMode $this.DevMode `
                            -WebSphereAdministratorCredential $this.WebSphereAdministratorCredential `
                            -PortalAdministratorCredential $this.PortalAdministratorCredential `
                            -SourcePath $this.SourcePath `
                            -SourcePathCredential $this.SourcePathCredential `
                            -SetupCredential $this.SetupCredential
                    if ($updated) {
                        Write-Verbose "IBM WebSphere Portal Cumulative Fix: $cfLevelStr Applied Successfully"
                    } else {
                        Write-Error "Unable to install Portal Cumulative Fix. An unknown error occurred, please check logs"
                    }
                } else {
                    Write-Error "Unable to install Portal Cumulative Fix. Portal not installed"
                }
            } else {
                Write-Verbose "Uninstalling IBM WebSphere Portal Cumulative Fix (Not Yet Implemented)"
            }
        } catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }
    
    # Tests if the resource is in the desired state.
    [bool] Test() {
        Write-Verbose "Checking the IBM WebSphere Portal Cumulative Fix installation"
        $wpConfiguredCorrectly = $false
        $wpRsrc = $this.Get()
        
        if (($wpRsrc.Ensure -eq $this.Ensure) -and ($wpRsrc.Ensure -eq [Ensure]::Present)) {
            if ($wpRsrc.Version -eq $this.Version) {
                if ($wpRsrc.PortalEdition -eq $this.PortalEdition) {
                    if ($wpRsrc.CFLevel -eq $this.CFLevel) {
                        Write-Verbose "IBM WebSphere Portal cumulative fixed installed"
                        $wpConfiguredCorrectly = $true
                    }
                }
            }
        } elseif (($wpRsrc.Ensure -eq $this.Ensure) -and ($wpRsrc.Ensure -eq [Ensure]::Absent)) {
            $wpConfiguredCorrectly = $true
        }

        if (!($wpConfiguredCorrectly)) {
            Write-Verbose "IBM WebSphere Portal Cumulative Fix not configured correctly"
        }
        
        return $wpConfiguredCorrectly
    }
    
    # Gets the resource's current state.
    [cIBMWebSpherePortalCumulativeFix] Get() {
        $RetEnsure = [Ensure]::Absent
        $RetVersion = $null
        $RetWPEdition = $null
        $RetInsDir = $null
        $RetCFLevel = $null

        # Check if WAS ND is installed / Portal depends on it
        $WASInsDir = Get-IBMWebSphereAppServerInstallLocation -WASEdition ND
        
        if($WASInsDir -and (Test-Path($WASInsDir))) {
            Write-Verbose "IBM WAS ND is Present"
            # Attempt to retrieve the Portal version information
            $instDir = (Split-Path $WASInsDir)
            $portalDir = Join-Path $instDir "PortalServer"
            if ($portalDir -and (Test-Path $portalDir)) {
                $wpVersionInfo = Get-IBMWebSpherePortalVersionInfo -ErrorAction Continue
                if ($wpVersionInfo -and $wpVersionInfo["Product Directory"]) {
                    Write-Verbose "IBM WebSphere Portal is Present"
                    $portalHome = $wpVersionInfo["Product Directory"]
                    $RetEnsure = [Ensure]::Present
                    if ($portalHome) {
                        $RetInsDir = $instDir
                        $wpEdition = $this.PortalEdition.ToString()
                        # Ensure that it is the right Portal Edition (i.e. WCM vs EXPRESS vs MP)
                        if ($wpVersionInfo.Products[$wpEdition]) {
                            $RetWPEdition = $this.PortalEdition
                            $RetVersion = $wpVersionInfo.Products[$wpEdition].Version
                            $RetCFLevel = $wpVersionInfo.Products[$wpEdition]."Installed Fix"
                        } elseif ($wpVersionInfo.Products.Keys.Count -gt 0) {
                            ForEach ($wpProduct in $wpVersionInfo.Products.Keys) {
                                if (!((@('MP','CFGFW')).Contains($wpProduct))) {
                                    $RetWPEdition = $wpProduct
                                    $RetVersion = $wpVersionInfo.Products[$wpProduct].Version
                                    $RetCFLevel = $wpVersionInfo.Products[$wpProduct]."Installed Fix"
                                    break;
                                }
                            }
                            if (!($RetWPEdition)) {
                                $RetWPEdition = [PortalEdition]::MP
                                $RetVersion = $wpVersionInfo.Products.MP.Version
                                $RetCFLevel = $wpVersionInfo.Products.MP."Installed Fix"
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
        }
        if ($RetCFLevel) {
            [int] $cfNumber = [int]$RetCFLevel.Substring(2)
            $returnValue.Add('CFLevel', $cfNumber)
        }
        if ($RetWPEdition -ne $null) {
            $returnValue.Add('PortalEdition', $RetWPEdition)
        }

        return $returnValue
    }
}

[DscResource()]
class cIBMWebSpherePortalDatabase {
    
    [DscProperty(Mandatory)]
    [Ensure] $Ensure
    
    [DscProperty()]
    [DatabaseType] $PortalDatabaseType
    
    [DscProperty(Key)]
    [String] $DatabaseHostName

    [DscProperty()]
    [String] $DatabaseInstanceHomeDirectory

    [DscProperty()]
    [String] $DatabaseInstanceName

    [DscProperty()]
    [Int] $DatabasePort = 1433
    
    [DscProperty()]
    [String] $JDBCDriverPath

    [DscProperty()]
    [hashtable] $RelDBConfig = @{
                    DomainName = "release"
                    DatabaseName = "reldb"
                    Schema = "relusr"
                    DataSourceName = "relDS"
                }
    
    [DscProperty()]
    [hashtable] $CommDBConfig = @{
                    DomainName = "community"
                    DatabaseName = "commdb"
                    Schema = "commusr"
                    DataSourceName = "commDS"
                }
    
    [DscProperty()]
    [hashtable] $CustDBConfig = @{
                    DomainName = "customization"
                    DatabaseName = "custdb"
                    Schema = "custusr"
                    DataSourceName = "custDS"
                }
    
    [DscProperty()]
    [hashtable] $JcrDBConfig = @{
                    DomainName = "jcr"
                    DatabaseName = "jcrdb"
                    Schema = "jcrusr"
                    DataSourceName = "jcrdbDS"
                }
    
    [DscProperty()]
    [hashtable] $LmDBConfig = @{
                    DomainName = "likeminds"
                    DatabaseName = "lmdb"
                    Schema = "lmusr"
                    DataSourceName = "lmDS"
                }
    
    [DscProperty()]
    [hashtable] $FdbkDBConfig = @{
                    DomainName = "feedback"
                    DatabaseName = "fdbkdb"
                    Schema = "fdbkusr"
                    DataSourceName = "fdbkDS"
                }
    
    [DscProperty()]
    [PSCredential] $DBACredential

    [DscProperty(Mandatory)]
    [PSCredential] $WebSphereAdministratorCredential

    [DscProperty()]
    [PSCredential] $DBUserCredential
    
    [DscProperty()]
    [bool] $SameDBCredentials = $true

    [DscProperty()]
    [PSCredential] $RelDBCredential
    
    [DscProperty()]
    [PSCredential] $CommDBCredential
    
    [DscProperty()]
    [PSCredential] $CustDBCredential
    
    [DscProperty()]
    [PSCredential] $JcrDBCredential
    
    [DscProperty()]
    [PSCredential] $LmDBCredential
    
    [DscProperty()]
    [PSCredential] $FdbkDBCredential
    
    # Sets the desired state of the resource.
    [void] Set() {
        try {
            if ($this.Ensure -eq [Ensure]::Present) {
                [string] $dbTypeStr = $this.PortalDatabaseType.ToString()
                Write-Verbose "Starting Portal Database Transfer to $dbTypeStr ($this.DatabaseHostName)"
                [hashtable] $PortalDBConfig = @{
                    DbDomains = @()
                }
                $PortalDBConfig.DbDomains += $this.RelDBConfig
                $PortalDBConfig.DbDomains += $this.CommDBConfig
                $PortalDBConfig.DbDomains += $this.CustDBConfig
                $PortalDBConfig.DbDomains += $this.JcrDBConfig
                $PortalDBConfig.DbDomains += $this.LmDBConfig
                $PortalDBConfig.DbDomains += $this.FdbkDBConfig
                if ($this.SameDBCredentials) {
                    $this.RelDBCredential = $this.DBUserCredential
                }
                Invoke-DatabaseTransfer -PortalDatabaseType $this.PortalDatabaseType `
                    -DatabaseHostName $this.DatabaseHostName -DatabaseInstanceName $this.DatabaseInstanceName `
                    -DatabasePort $this.DatabasePort -DatabaseInstanceHomeDirectory $this.DatabaseInstanceHomeDirectory `
                    -PortalDBConfig $PortalDBConfig -JDBCDriverPath $this.JDBCDriverPath `
                    -WebSphereAdministratorCredential $this.WebSphereAdministratorCredential `
                    -DBACredential $this.DBACredential -RelDBCredential $this.RelDBCredential `
                    -SameDBCredentials $this.SameDBCredentials -CommDBCredential $this.CommDBCredential `
                    -CustDBCredential $this.CustDBCredential -JcrDBCredential $this.JcrDBCredential `
                    -LmDBCredential $this.LmDBCredential -FdbkDBCredential $this.FdbkDBCredential -ErrorAction Stop
            } else {
                Write-Verbose "Operation not allowed.  You can't rollback a database transfer"
            }
        } catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }
    
    # Tests if the resource is in the desired state.
    [bool] Test() {
        Write-Verbose "Checking the IBM WebSphere Portal Database Configuration"
        $wpDBConfiguredCorrectly = $false
        $wpDBRsrc = $this.Get()
        
        if (($wpDBRsrc.Ensure -eq $this.Ensure) -and ($wpDBRsrc.Ensure -eq [Ensure]::Present)) {
            if ($wpDBRsrc.PortalDatabaseType -eq $this.PortalDatabaseType) {
                if ($wpDBRsrc.DatabaseHostName -eq $this.DatabaseHostName) {
                    if ($wpDBRsrc.DatabasePort -eq $this.DatabasePort) {
                        Write-Verbose "IBM WebSphere Portal Database configured correctly"
                        $wpDBConfiguredCorrectly = $true
                        #TODO: Perform more testing
                    }
                }
            }
        } elseif (($wpDBRsrc.Ensure -eq $this.Ensure) -and ($wpDBRsrc.Ensure -eq [Ensure]::Absent)) {
            $wpDBConfiguredCorrectly = $true
        }

        if (!($wpDBConfiguredCorrectly)) {
            Write-Verbose "IBM WebSphere Portal Database not configured correctly"
        }
        
        return $wpDBConfiguredCorrectly
    }
    
    # Gets the portal's current database configuration
    [cIBMWebSpherePortalDatabase] Get() {
        $RetEnsure = [Ensure]::Absent
        $RetDBHostname = $null
        $RetDatabasePort = $null
        $RetPortalDatabaseType = $null
        
        $portalcfg = Get-IBMPortalConfig
        [hashtable] $wasTopology = Get-IBMWebSphereTopology -ProfilePath $portalcfg["ProfilePath"]

        $cellName = $wasTopology.Keys[0]
        $nodeName = ($wasTopology[$cellName]).GetValue(0).Keys[0]
        $serverName = (($wasTopology[$cellName]).GetValue(0)[$nodeName]).GetValue(0)
        $resourcesXMLPath = Join-Path $portalcfg["ProfilePath"] "config/cells/$cellName/nodes/$nodeName/servers/$serverName/resources.xml"

        $sqlProviderType = "Microsoft SQL Server JDBC Driver (XA)"

        $RetRelDBConfig = @{ DomainName = "release" }
        $RetCommDBConfig = @{ DomainName = "community" }
        $RetCustDBConfig = @{ DomainName = "customization" }
        $RetJcrDBConfig = @{ DomainName = "jcr" }
        $RetLmDBConfig = @{ DomainName = "likeminds" }
        $RetFdbkDBConfig = @{ DomainName = "feedback" }

        $dbType = $null

        if (Test-Path $resourcesXMLPath) {
            Write-Host "File found" -ForegroundColor DarkYellow
            [XML] $resourcesXML = Get-Content $resourcesXMLPath
            $rootNode = $resourcesXML.ChildNodes[1]
            $ns = New-Object System.Xml.XmlNamespaceManager($resourcesXML.NameTable)
            $ns.AddNamespace("resources.env","http://www.ibm.com/websphere/appserver/schemas/5.0/resources.env.xmi")
            $dataStorePropSet = $resourcesXML.SelectSingleNode("//resources.env:ResourceEnvironmentProvider[@name='WP DataStoreService']/propertySet", $ns)
            $dataStorePropSet.ChildNodes | % {
                $varName = $_.Attributes.GetNamedItem("name")
                $varValue = $_.Attributes.GetNamedItem("value")
                if ($varName.Value -eq "rel.datasource.schema") {
                    $RetRelDBConfig["Schema"] = $varValue.Value 
                } elseif ($varName.Value -eq "cust.datasource.schema") {
                    $RetCustDBConfig["Schema"] = $varValue.Value 
                } elseif ($varName.Value -eq "comm.datasource.schema") {
                    $RetCommDBConfig["Schema"] = $varValue.Value 
                } elseif ($varName.Value -eq "jcr.datasource.schema") {
                    $RetJcrDBConfig["Schema"] = $varValue.Value 
                } elseif ($varName.Value -eq "rel.datasource.dbms") {
                    $dbType = $varValue.Value
                }
            }
            $lmProps = Get-JavaProperties -PropertyFilePath (Join-Path $portalcfg["ProfilePath"] "PortalServer/config/config/services/LikeMindsService.properties") -PropertyList @("likeminds.schema")
            if ($lmProps -and $lmProps["likeminds.schema"]) {
                $RetLmDBConfig["Schema"] = $lmProps["likeminds.schema"]
            }
            $fdbkProps = Get-JavaProperties -PropertyFilePath (Join-Path $portalcfg["ProfilePath"] "PortalServer/config/config/services/FeedbackService.properties") -PropertyList @("schemaName")
            if ($fdbkProps -and $fdbkProps["schemaName"]) {
                $RetFdbkDBConfig["Schema"] = $fdbkProps["schemaName"]
            }
            $ns = New-Object System.Xml.XmlNamespaceManager($resourcesXML.NameTable)
            $ns.AddNamespace("resources.jdbc","http://www.ibm.com/websphere/appserver/schemas/5.0/resources.jdbc.xmi")
            $jdbcFactories = $resourcesXML.SelectNodes("//resources.jdbc:JDBCProvider[@name='wpdbJDBC_$dbType']/factories", $ns)
            $jdbcFactories | % {
                $varName = $_.Attributes.GetNamedItem("name")
                $varDesc = $_.Attributes.GetNamedItem("description")
                $ampIdx = $varDesc.Value.IndexOf("&&&")+3
                $domainName = $varDesc.Value.Substring($ampIdx,$varDesc.Value.IndexOf(",&&&")-$ampIdx)
                if ($domainName -eq "release") {
                    $RetRelDBConfig["DataSourceName"] = $varName.Value
                } elseif ($domainName -eq "customization") {
                    $RetCustDBConfig["DataSourceName"] = $varName.Value
                } elseif ($domainName -eq "community") {
                    $RetCommDBConfig["DataSourceName"] = $varName.Value
                } elseif ($domainName -eq "jcr") {
                    $RetJcrDBConfig["DataSourceName"] = $varName.Value
                } elseif ($domainName -eq "likeminds") {
                    $RetLmDBConfig["DataSourceName"] = $varName.Value
                } elseif ($domainName -eq "feedback") {
                    $RetFdbkDBConfig["DataSourceName"] = $varName.Value
                }
                $_.FirstChild.ChildNodes | % {
                    $subName = $_.Attributes.GetNamedItem("name")
                    $subValue = $_.Attributes.GetNamedItem("value")
                    if ($subName.Value -eq "databaseName") {
                        if ($domainName -eq "release") {
                            $RetRelDBConfig["DatabaseName"] = $subValue.Value
                        } elseif ($domainName -eq "customization") {
                            $RetCustDBConfig["DatabaseName"] = $subValue.Value
                        } elseif ($domainName -eq "community") {
                            $RetCommDBConfig["DatabaseName"] = $subValue.Value
                        } elseif ($domainName -eq "jcr") {
                            $RetJcrDBConfig["DatabaseName"] = $subValue.Value
                        } elseif ($domainName -eq "likeminds") {
                            $RetLmDBConfig["DatabaseName"] = $subValue.Value
                        } elseif ($domainName -eq "feedback") {
                            $RetFdbkDBConfig["DatabaseName"] = $subValue.Value
                        }
                    } elseif (($subName.Value -eq "serverName") -and ($domainName -eq "release")) {
                        $RetDBHostname = $subValue.Value
                    } elseif (($subName.Value -eq "portNumber") -and ($domainName -eq "release")) {
                        $RetDatabasePort = $subValue.Value
                    }
                }
            }
            
            if ($dbType -eq "sqlserver2005") {
                $RetPortalDatabaseType = [DatabaseType]::SQLSERVER
                $RetEnsure = [Ensure]::Present
            } else {
                $RetPortalDatabaseType = [DatabaseType]::DERBY
            }
        }
        
        $returnValue = @{
            Ensure = $RetEnsure
            DatabaseHostName = $RetDBHostname
            PortalDatabaseType = $RetPortalDatabaseType
            DatabasePort = $RetDatabasePort
            RelDBConfig = $RetRelDBConfig
            CustDBConfig = $RetCustDBConfig
            CommDBConfig = $RetCommDBConfig
            JcrDBConfig = $RetJcrDBConfig
            LmDBConfig = $RetLmDBConfig
            FdbkDBConfig = $RetFdbkDBConfig
        }
        
        return $returnValue
    }
}