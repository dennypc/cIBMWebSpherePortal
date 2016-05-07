##############################################################################################################
########                                 IBM WebSphere Portal CmdLets                                #########
##############################################################################################################

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
    ServerName
    Version
    CFLevel
    ConfigWizardProfilePath
}

$PortalConfigPropertyMap = @{
    ([PortalConfig]::Edition.ToString()) = "WPFamilyName";
    ([PortalConfig]::PortalHome.ToString()) = "PortalRootDir";
    ([PortalConfig]::ProfileName.ToString()) = "ProfileName";
    ([PortalConfig]::ProfilePath.ToString()) = "ProfileDirectory";
    ([PortalConfig]::Version.ToString()) = "version";
    ([PortalConfig]::CFLevel.ToString()) = "fixlevel";
    ([PortalConfig]::ConfigWizardProfilePath.ToString()) = "cwProfileHome"
}

##############################################################################################################
# Get-IBMWebSpherePortalInstallLocation
#   Returns the location where IBM WebSphere Application Server is installed
##############################################################################################################
Function Get-IBMWebSpherePortalInstallLocation() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory=$false,position=0)]
        [System.Version] $Version = "8.5.0.0"
    )
    $wpHome = $null
    $wasInstDir = Get-IBMWebSphereAppServerInstallLocation -WASEdition ND -Version $Version
    if ($wasInstDir) {
        $wpHome = Join-Path (Split-Path $wasInstDir) "PortalServer"
        if ($wpHome -and (Test-Path $wpHome -PathType Container)) {
            Write-Debug "Get-IBMWebSpherePortalInstallLocation returning $wpHome"
        } else {
            $wpHome = $null
        }
    }
    Return $wpHome
}

##############################################################################################################
# Get-IBMWPSProperties
#   Returns the global wps.properties
##############################################################################################################
Function Get-IBMWPSProperties() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param ()
    [hashtable] $wpsProps = @{}
    $wpHome = Get-IBMWebSpherePortalInstallLocation
    $wpsPropsPath = Join-Path $wpHome "wps.properties"
    if (Test-Path $wpsPropsPath -PathType Leaf) {
        $wpsProps = Get-JavaProperties -PropertyFilePath $wpsPropsPath
    }
    Return $wpsProps
}

##############################################################################################################
# Get-IBMPortalConfig
#   Returns a hashtable of Portal Config settings, using the PortalConfig enum as key
##############################################################################################################
Function Get-IBMPortalConfig() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param ()
    [hashtable] $wpsProps = Get-IBMWPSProperties
    [hashtable] $portalConfigMap = @{}
    if ($wpsProps -and ($wpsProps.Count -gt 0)) {
        [string] $wpEdition = $wpsProps[$PortalConfigPropertyMap[[PortalConfig]::Edition.ToString()]]
        $portalConfigMap.Add(([PortalConfig]::Edition.ToString()), [System.Enum]::Parse([PortalEdition], $wpEdition, $true))
        
        [string] $wpHome = $wpsProps[$PortalConfigPropertyMap[[PortalConfig]::PortalHome.ToString()]]
        $wpHome = [IO.Path]::GetFullPath($wpHome)
        $portalConfigMap.Add(([PortalConfig]::PortalHome.ToString()), $wpHome)
        
        $portalConfigMap.Add(([PortalConfig]::ProfileName.ToString()), $wpsProps[$PortalConfigPropertyMap[[PortalConfig]::ProfileName.ToString()]])
        
        [string] $profilePath = $wpsProps[$PortalConfigPropertyMap[[PortalConfig]::ProfilePath.ToString()]]
        $profilePath = [IO.Path]::GetFullPath($profilePath)
        $portalConfigMap.Add(([PortalConfig]::ProfilePath.ToString()), $profilePath)
        
        [string] $versionStr = $wpsProps[$PortalConfigPropertyMap[[PortalConfig]::Version.ToString()]]
        [version] $versionObj = (New-Object -TypeName System.Version -ArgumentList $versionStr)
        $portalConfigMap.Add(([PortalConfig]::Version.ToString()), $versionObj)

        [string] $cfStr = $wpsProps[$PortalConfigPropertyMap[[PortalConfig]::CFLevel.ToString()]]
        [int] $cfNumber = 0
        if ($cfStr -and ($cfStr.Length -gt 1)) {
            $cfNumber = [int]$cfStr.Substring(2)
        }
        
        $portalConfigMap.Add(([PortalConfig]::CFLevel.ToString()), $cfNumber)

        [string] $cwProfilePath = $wpsProps[$PortalConfigPropertyMap[[PortalConfig]::ConfigWizardProfilePath.ToString()]]
        $cwProfilePath = [IO.Path]::GetFullPath($cwProfilePath)
        $portalConfigMap.Add(([PortalConfig]::ConfigWizardProfilePath.ToString()), $cwProfilePath)
        
        $cfgEnginePath = Join-Path $profilePath "ConfigEngine"
        $portalConfigMap.Add(([PortalConfig]::ProfileConfigEnginePath.ToString()), $cfgEnginePath)
        
        $wkplcPropertiesFile = Join-Path $cfgEnginePath "properties\wkplc.properties"
        $wkplcProps = Get-JavaProperties -PropertyFilePath $wkplcPropertiesFile -PropertyList @("ServerName")
        $portalConfigMap.Add(([PortalConfig]::ServerName.ToString()), $wkplcProps["ServerName"])
    }
    Return $portalConfigMap
}

##############################################################################################################
# Get-IBMWebSpherePortalVersionInfo
#   Returns a hashtable containing version information of the IBM Portal Product/Components installed
##############################################################################################################
Function Get-IBMWebSpherePortalVersionInfo() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param ()
    
    $portalConfig = Get-IBMPortalConfig
    $portalHome = $portalConfig[[PortalConfig]::PortalHome.ToString()]

    Write-Verbose "Get-IBMWebSpherePortalVersionInfo::ENTRY"
    
    #Validate Parameters
    [string] $versionInfoBat = Join-Path $portalHome "bin\WPVersionInfo.bat"
    if (!(Test-Path($versionInfoBat))) {
        Write-Error "Invalid path: $versionInfoBat not found"
        Return $null
    }
        
    [hashtable] $VersionInfo = @{}
    $versionInfoProcess = Invoke-ProcessHelper -ProcessFileName $versionInfoBat
    
    if ($versionInfoProcess -and ($versionInfoProcess.ExitCode -eq 0)) {
        $output = $versionInfoProcess.StdOut
        if ($output) {
            # Parse installation info
            $matchFound = $output -match "\nInstallation\s+\n\-+\s\n((.|\n)*?)Technology\sList"
            if ($matchFound -and $matches -and ($matches.Count -gt 1)) {
                $matches[1] -Split "\n" | % {
                    $matchLine = $_.trim()
                    if (!([string]::IsNullOrEmpty($matchLine))) {
                        $nameValue = $matchLine -split "\s\s+"
                        $VersionInfo.Add($nameValue[0].trim(), $nameValue[1].trim())
                    }
                }
            }
            # Parse list of installed products
            $matchFound = $output -match "\nTechnology\sList\s+\n\-+\s\n((.|\n)*?)Installed\sProduct"
            if ($matchFound -and $matches -and ($matches.Count -gt 1)) {
                [hashtable] $products = @{}
                $matches[1] -Split "\n" | % {
                    $matchLine = $_.trim()
                    if (!([string]::IsNullOrEmpty($matchLine))) {
                        $nameValue = $matchLine -split "\s\s+"
                        $products.Add($nameValue[0].trim(), $null)
                    }
                }

                # Parse product specific info
                $pattern = "Installed\s(Product|Component)\s+\n\-+\s\n(.|\n)*?\n\s((\n|\nPackage)*?)"
                $output | Select-String -AllMatches $pattern | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value | % {
                    $prodMatchFound = $_ -match "Installed\s(Product|Component)\s+\n\-+\s\n((.|\n)*?)\n\s"
                    if ($prodMatchFound -and $matches -and ($matches.Count -gt 1)) {
                        [hashtable] $product = @{}
                        $currentKey = $null
                        $matches[2] -Split "\n" | % {
                            [string] $matchLine = $_.trim()
                            if (!([string]::IsNullOrEmpty($matchLine))) {
                                if ($matchLine.IndexOf("  ") -gt 0) {
                                    $nameValue = $matchLine -split "\s\s+"
                                    if ($nameValue) {
                                        $currentKey = $nameValue[0].trim()
                                        $product.Add($currentKey, $nameValue[1].trim())
                                    }
                                } else {
                                    $valueArray = @()
                                    $currentValue = $product[$currentKey]
                                    $valueArray += $currentValue
                                    $valueArray += $matchLine
                                    $product[$currentKey] = $valueArray
                                }
                            }
                        }
                        if (($product.Count -gt 0) -and $products.ContainsKey($product.ID)) {
                            $products[$product.ID] = $product
                        }
                    }
                }
                $VersionInfo.Add("Products", $products)
            } else {
                Write-Error "Unable to parse any product from output: $output"
            }
        } else {
            Write-Error "No output returned from WPVersionInfo.bat"
        }
    } else {
        $errorMsg = (&{if($versionInfoProcess) {$versionInfoProcess.StdOut} else {$null}})
        Write-Error "An error occurred while executing the WPVersionInfo.bat process: $errorMsg"
    }
    
    return $VersionInfo
}

##############################################################################################################
# Get-IBMWebSpherePortalFixesInstalled
#   Returns an array containing the list of the IBM WebSphere Portal interim fixes installed
##############################################################################################################
Function Get-IBMWebSpherePortalFixesInstalled() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param ()
    
    $portalConfig = Get-IBMPortalConfig
    $portalHome = $portalConfig[[PortalConfig]::PortalHome.ToString()]
    
    [string[]] $installedFixes = @()
    $wpver_bat = Join-Path $portalHome "bin\WPVersionInfo.bat"
    $wpver_args = @("-fixes")
    $versionInfoProcess = Invoke-ProcessHelper -ProcessFileName $wpver_bat -ProcessArguments $wpver_args
    
    if ($versionInfoProcess -and ($versionInfoProcess.ExitCode -eq 0)) {
        $fixesOutput = ($versionInfoProcess.StdOut) -split "\n"
        $fixesOutput | Select-String -Pattern "^(Ifix ID\s\s)" -CaseSensitive | % {
            $installedFixes += ((($_.Line).Substring("Ifix ID".Length)).Trim())
        }
    }
    
    return $installedFixes
}

##############################################################################################################
# Install-IBMWebSpherePortal
#   Installs IBM WebSphere Portal on the current machine
##############################################################################################################
Function Install-IBMWebSpherePortal() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory = $true)]
		[System.String]
		$InstallMediaConfig,
        
        [parameter(Mandatory = $true)]
		[System.String]
		$ResponseFileTemplate,
        
		[System.String]
    	$InstallationDirectory = "C:\IBM\WebSphere\",
        
        [parameter(Mandatory = $true)]
		[System.String]
    	$IMSharedLocation,
        
        [System.String]
        $CellName = "wpCell",
        
        [System.String]
        $ProfileName = "wp_profile",

        [System.String]
        $NodeName = "wpNode",
        
        [System.String]
        $ServerName = "WebSphere_Portal",
        
        [parameter(Mandatory = $true)]
        [System.String]
		$HostName,
        
        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $WebSphereAdministratorCredential,
        
        [System.Management.Automation.PSCredential]
        $PortalAdministratorCredential,

    	[parameter(Mandatory = $true)]
		[System.String]
		$SourcePath,

        [System.Management.Automation.PSCredential]
		$SourcePathCredential
	)
    
    $installed = $false
    # Populate variables needed by response file templates
    [Hashtable] $Variables = @{}
    if (!($IMSharedLocation.EndsWith([System.IO.Path]::DirectorySeparatorChar)) -and !($IMSharedLocation.EndsWith([System.IO.Path]::AltDirectorySeparatorChar))) {
        $Variables.Add("sharedLocation", ($IMSharedLocation + [System.IO.Path]::DirectorySeparatorChar))
    } else {
        $Variables.Add("sharedLocation", $IMSharedLocation)
    }
    if (!($InstallationDirectory.EndsWith([System.IO.Path]::DirectorySeparatorChar)) -and !($InstallationDirectory.EndsWith([System.IO.Path]::AltDirectorySeparatorChar))) {
        $Variables.Add("wasInstallLocation", ($InstallationDirectory + [System.IO.Path]::DirectorySeparatorChar))
    } else {
        $Variables.Add("wasInstallLocation", $InstallationDirectory)
    }
    
    $Variables.Add("cellName", $CellName)
    $Variables.Add("profileName", $ProfileName)
    $Variables.Add("nodeName", $NodeName)
    $Variables.Add("hostName", $HostName)
    $Variables.Add("wasadmin", $WebSphereAdministratorCredential.UserName)
    $Variables.Add("wasadminPwd", $WebSphereAdministratorCredential)
    if ($PortalAdministratorCredential) {
        $Variables.Add("wpadmin", $PortalAdministratorCredential.UserName)
        $Variables.Add("wpadminPwd", $PortalAdministratorCredential)
    } else {
        $Variables.Add("wpadmin", $WebSphereAdministratorCredential.UserName)
        $Variables.Add("wpadminPwd", $WebSphereAdministratorCredential)
    }
    
    # Install Portal via IBM Installation Manager
    $installed = Install-IBMProduct -InstallMediaConfig $InstallMediaConfig `
        -ResponseFileTemplate $ResponseFileTemplate -Variables $Variables `
        -SourcePath $SourcePath -SourcePathCredential $SourcePathCredential -ErrorAction Stop
    
    Write-Verbose "IBM WebSphere Portal installation process finished"
    
    $wpProfileHome = Join-Path -Path $InstallationDirectory -ChildPath $ProfileName
    $WASInsDir = Get-IBMWebSphereAppServerInstallLocation -WASEdition ND
    
    if ($installed -and (Test-Path($wpProfileHome)) -and $WASInsDir -and (Test-Path($WASInsDir))) {
        $installed = $false
        # Create a windows service for the WAS server
        Write-Verbose "Creating windows service for portal"
        $wasWinSvcName = New-IBMWebSphereAppServerWindowsService -ProfilePath $wpProfileHome -ServerName $ServerName `
                            -WASEdition ND -WebSphereAdministratorCredential $WebSphereAdministratorCredential
        if ($wasWinSvcName -and (Get-Service -DisplayName $wasWinSvcName)) {
            # Restart Portal
            Write-Verbose "Restarting portal via batch for first time - Windows Service will be used going forward"
            Stop-WebSpherePortal -WebSphereAdministratorCredential $WebSphereAdministratorCredential
            # Start via Windows Service
            Start-WebSpherePortal $ServerName $WebSphereAdministratorCredential
            
            $portalConfig = Get-IBMPortalConfig
            # Stop default Config Wizard server if started
            $cwProfileDir = $portalConfig[[PortalConfig]::ConfigWizardProfilePath.ToString()]
            if (Test-Path($cwProfileDir)) {
                Write-Verbose "Stopping Config Wizard server as is not needed"
                Stop-WebSphereServerViaBatch "server1" $cwProfileDir $WebSphereAdministratorCredential
            }
            
            Write-Verbose "IBM WebSphere Windows Service configured successfully"
            $installed = $true
        } else {
            Write-Verbose "IBM WebSphere Portal was not installed correctly (Windows Service Does Not Exists).  Please check the installation logs"
        }
    } else {
        Write-Verbose "An error occurred while installing IBM WebSphere Portal, please check installation logs"
    }

    Return $installed
}

##############################################################################################################
# Invoke-ConfigEngine
#   Wrapper cmdlet for running ConfigEngine.  Returns object with stdout,stderr, and exit code
##############################################################################################################
Function Invoke-ConfigEngine() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param (
        [parameter(Mandatory=$true,position=0)]
        [string] $Path,

        [parameter(Mandatory=$true,position=1)]
        [string[]] $Tasks,
        
        [parameter(Mandatory=$false,position=2)]
        [string] $OutputFilter,

        [parameter(Mandatory=$false,position=3)]
        [PSCredential] $WebSphereAdministratorCredential,
        
        [parameter(Mandatory=$false,position=4)]
        [PSCredential] $PortalAdministratorCredential,
        
        [switch]
        $DiscardStandardOut,

        [switch]
        $DiscardStandardErr
    )

    $success = $false
    
    [PSCustomObject] $cfgEngineProcess = @{
        StdOut = $null
        StdErr = $null
        ExitCode = $null
    }

    $cfgEngineBatch = Join-Path -Path $Path -ChildPath "ConfigEngine.bat"

    if (Test-Path($cfgEngineBatch)) {
        if ($WebSphereAdministratorCredential) {
            $wasPwd = $WebSphereAdministratorCredential.GetNetworkCredential().Password
            $Tasks += "-DWasPassword=$wasPwd"
        }
        if ($PortalAdministratorCredential) {
            $wpPwd = $PortalAdministratorCredential.GetNetworkCredential().Password
            $Tasks += "-DPortalAdminPwd=$wpPwd"
        } elseif ($WebSphereAdministratorCredential) {
            $wasPwd = $WebSphereAdministratorCredential.GetNetworkCredential().Password
            $Tasks += "-DPortalAdminPwd=$wasPwd"
        }
        
        $discStdOut = $DiscardStandardOut.IsPresent
        $discStdErr = $DiscardStandardErr.IsPresent

        $cfgEngineProcess = Invoke-ProcessHelper -ProcessFileName $cfgEngineBatch -ProcessArguments $Tasks `
                                -WorkingDirectory $Path -DiscardStandardOut:$discStdOut -DiscardStandardErr:$discStdErr
        if ($cfgEngineProcess -and (!($cfgEngineProcess.StdErr)) -and ($cfgEngineProcess.ExitCode -eq 0)) {
            $buildFailures = Select-String -InputObject $cfgEngineProcess.StdOut -Pattern "BUILD FAILED" -AllMatches
            $success = ($buildFailures.Matches.Count -eq 0)
            if ($success -and (!([string]::IsNullOrEmpty($OutputFilter)))) {
                [string[]] $filteredOutput = $null
                ($cfgEngineProcess.StdOut -split [environment]::NewLine) | ? {
                    if (([string]$_).Contains($OutputFilter)) {
                        $filteredOutput += $_
                    }
                }
                if ($filteredOutput) {
                    $cfgEngineProcess.StdOut = $filteredOutput
                }
            } else {
                if (!($success)) {
                    Write-Error "Build failures detected in ConfigEngine, please check ConfigEngine.log"
                }
            }
        } else {
            $errorMsg = $null
            if ($cfgEngineProcess -and $cfgEngineProcess.StdErr) {
                $errorMsg = $cfgEngineProcess.StdErr
            } else {
                $errorMsg = $cfgEngineProcess.StdOut
            }
            $exitCode = (&{if($cfgEngineProcess) {$cfgEngineProcess.ExitCode} else {$null}})
            Write-Error "An error occurred while executing ConfigEngine.bat process. ExitCode: $exitCode Mesage: $errorMsg"
        } 
    } else {
        Write-Error "Config Engine Batch file not found on directory $Path"
    }
    
    if (!$success -and ($cfgEngineProcess.ExitCode -eq 0)) {
        $cfgEngineProcess.ExitCode = -1
    }

    Return $cfgEngineProcess
}

##############################################################################################################
# Test-WebSpherePortalStarted
#   Checks to see if Portal is already started
##############################################################################################################
Function Test-WebSpherePortalStarted {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory=$true,position=0)]
        [String] $ServerName,
        
        [parameter(Mandatory=$true,position=1)]
        [String] $PortalPIDFile
    )
    
    if (Test-WebSphereServerService -ServerName $ServerName) {
        Return $true
    } else {
        if (Test-Path $PortalPIDFile) {
            Return $true
        } else {
            Return $false
        }
    }
}

##############################################################################################################
# Start-WebSpherePortal
#   Starts WebSphere Portal using Windows Service or via batch if service not available
##############################################################################################################
Function Start-WebSpherePortal {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory=$false,position=0)]
        [string] $ServerName,
        
        [parameter(Mandatory=$false,position=1)]
        [PSCredential] $WebSphereAdministratorCredential
    )
    
    $portalConfig = Get-IBMPortalConfig
    
    if (!($ServerName) -and $WebSphereAdministratorCredential) {
        $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
        Invoke-ConfigEngine -Path $cfgEnginePath -Tasks "start-portal-server" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
    } elseif ($ServerName) {
        $wpProfilePath = $portalConfig[[PortalConfig]::ProfilePath.ToString()]
        $wpLogRoot = Join-Path $wpProfilePath "logs\$ServerName"
        $portalPidFile = Join-Path $wpLogRoot "$ServerName.pid"
        
        if (!(Test-WebSpherePortalStarted $ServerName $portalPidFile)) {
            if (Test-WebSphereServerServiceExists -ServerName $ServerName) {
                Start-WebSphereServer -ServerName $ServerName
            } else {
                Start-WebSphereServerViaBatch $ServerName $wpProfilePath
            }
            $sleepTimer = 0;
        
            Write-Verbose "Waiting for Portal PID file to be created: $portalPidFile"
        
            while(!(Test-Path $portalPidFile)) {
                sleep -s 10
                $sleepTimer += 10
                # Wait maximum of 10 minutes for portal to start after service is initialized
                if ($sleepTimer -ge 600) {
                    break
                }
            }
        }
    } else {
        Write-Error "You must specify either ServerName or WAS credentials (for ConfigEngine) to start the server"
    }
}

##############################################################################################################
# Test-WebSpherePortalStarted
#   Checks to see if Portal is already started
##############################################################################################################
Function Stop-WebSpherePortal {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory=$false,position=0)]
        [String] $ServerName,
        
        [parameter(Mandatory=$true,position=1)]
        [PSCredential] $WebSphereAdministratorCredential
    )
    
    $portalConfig = Get-IBMPortalConfig
    
    if (!($ServerName)) {
        $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
        Invoke-ConfigEngine -Path $cfgEnginePath -Tasks "stop-portal-server" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
    } else {
        $wpProfilePath = $portalConfig[[PortalConfig]::ProfilePath.ToString()]
        $wpLogRoot = Join-Path $wpProfilePath "logs\$ServerName"
        $portalPidFile = Join-Path $wpLogRoot "$ServerName.pid"
        if (!(Test-WebSpherePortalStarted $ServerName $portalPidFile)) {
            if (Test-WebSphereServerServiceExists -ServerName $ServerName) {
                Stop-WebSphereServer -ServerName $ServerName
            } else {
                Stop-WebSphereServerViaBatch $ServerName $wpProfilePath $WebSphereAdministratorCredential
            }
        }
        if (Test-Path $portalPidFile) {
            Write-Error "Unable to stop WebSphere Portal server, please check the stopServer.log for more information"
        }
    }
}

##############################################################################################################
# Install-IBMWebSpherePortalCumulativeFix
#   Installs IBM WebSphere Portal Cumulative Fix on the current machine
##############################################################################################################
Function Install-IBMWebSpherePortalCumulativeFix() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory = $true)]
        [int] $CFLevel,
        
        [bool] $DevMode = $false,
        
        [parameter(Mandatory = $true)]
        [PSCredential] $WebSphereAdministratorCredential,
        
        [PSCredential] $PortalAdministratorCredential,
        
    	[parameter(Mandatory = $true)]
		[string[]] $SourcePath,

        [PSCredential] $SourcePathCredential,
        
        [PSCredential] $SetupCredential
	)
    
    $portalConfig = Get-IBMPortalConfig
    
    $wpVersion = $portalConfig[[PortalConfig]::Version.ToString()]
    Write-Verbose "Installing CF: $CFLevel to Portal: $wpVersion"
    $updated = $False
    
    $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
    $wpHome = $portalConfig[[PortalConfig]::PortalHome.ToString()]
    
    # Temporarily update wkplc.properties with passwords
    $wpConfigPropertiesFile = Join-Path -Path $cfgEnginePath -ChildPath "properties\wkplc.properties"
    if (!(Test-Path($wpConfigPropertiesFile) -PathType Leaf)) {
        Write-Error "Unable to locate wkplc properties file"
        Return $false
    }
    # Backup Files
    Copy-Item -Path $wpConfigPropertiesFile -Destination "$wpConfigPropertiesFile.bak.$(get-date -f yyyyMMddHHmmss)"
    
    [hashtable] $wpconfigprops = @{}
    $wpconfigprops.Add("WasPassword", $WebSphereAdministratorCredential.GetNetworkCredential().Password)
    if ($PortalAdministratorCredential) {
        $wpconfigprops.Add("PortalAdminPwd", $PortalAdministratorCredential.GetNetworkCredential().Password)
    } else {
        $wpconfigprops.Add("PortalAdminPwd", $WebSphereAdministratorCredential.GetNetworkCredential().Password)
    }
    if (!($DevMode)) {
        $wpconfigprops.Add("PWordDelete", "true")
    }
    Set-JavaProperties $wpConfigPropertiesFile $wpconfigprops
    
    # Perform the right steps based on Portal Version / CF Level
    $baseVerObj = (New-Object -TypeName System.Version -ArgumentList "8.0.0.1")
    if ($wpVersion.CompareTo($baseVerObj) -ge 0) {
        if (($wpVersion.CompareTo($baseVerObj) -gt 0) -or (($wpVersion.CompareTo($baseVerObj) -eq 0) -and ($CFLevel -ge 15))) {
            [string] $productId = $null
            if ($wpVersion.CompareTo($baseVerObj) -eq 0) {
                $productId = "com.ibm.websphere.PORTAL.SERVER.v80"
            } else {
                $productId = "com.ibm.websphere.PORTAL.SERVER.v85"
            }
            
            [bool] $updated = $false
            
            if (Test-Path $wpHome -PathType Container) {
                # Stop Portal
                Stop-WebSpherePortal -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                
                Write-Verbose "Install CF binaries via IIM"
                $updated = Install-IBMProductViaCmdLine -ProductId $productId -InstallationDirectory $wpHome `
                            -SourcePath $SourcePath -SourcePathCredential $SourcePathCredential -ErrorAction Stop
                if ($updated) {
                    # Additional Configuration Steps
                    if ($wpVersion.ToString(2) -eq "8.5") {
                        if ($CFLevel -lt 8) {
                            Write-Verbose "Running PRE-APPLY-FIX config engine task (Mandatory until CF07)"
                            $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Tasks "PRE-APPLY-FIX"
                            if ($cfgEngineProc.ExitCode -eq 0) {
                                Write-Verbose "Running APPLY-FIX config engine task (Mandatory until CF07)"
                                $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Tasks "APPLY-FIX"
                                if ($cfgEngineProc.ExitCode -ne 0) {
                                    Write-Error "Error while executing config engine task: APPLY-FIX"
                                }
                            } else {
                                Write-Error "Error while executing config engine task: PRE-APPLY-FIX"
                            }
                        } else {
                            Write-Verbose "Apply patches for CF9/10"
                            if (($CFLevel -eq 9) -or ($CFLevel -eq 10)) {
                                # Look for patch in the temp directory
                                $patchFolder = Join-Path (Get-IBMInstallationManagerTempDir) "CF$CFLevel`Patch"
                                if (Test-Path $patchFolder) {
                                    # Patch Files
                                    $wpearPatchXML = Join-Path $patchFolder "wp.ear.fp_cfg.xml"
                                    $wpSimpleThemePatchXML = Join-Path $patchFolder "wp.theme.themes.simple_cfg.xml"
                                    $wpThemeDevSitePatchXML = Join-Path $patchFolder "wp.theme.themes.themedevsite_cfg.xml"
                                    # Original Files
                                    $wpearXML = Join-Path $wpHome "\installer\wp.ear\config\includes\wp.ear.fp_cfg.xml"
                                    $wpSimpleThemeXML = Join-Path $wpHome "\theme\wp.theme.themes\simple\config\includes\wp.theme.themes.simple_cfg.xml"
                                    $wpThemeDevSiteXML = Join-Path $wpHome "\theme\wp.theme.themes\themedevsite\config\includes\wp.theme.themes.themedevsite_cfg.xml"
                                    if ((Test-Path $wpearXML) -and (Test-Path $wpearPatchXML)) {
                                        Copy-Item $wpearPatchXML -Destination $wpearXML -Force -Verbose | Out-Null
                                    } else {
                                        Write-Warning "Unable to patch wp.ear.fp_cfg.xml, path not found"
                                    }
                                    if ((Test-Path $wpSimpleThemeXML) -and (Test-Path $wpSimpleThemePatchXML)) {
                                        Copy-Item $wpSimpleThemePatchXML -Destination $wpSimpleThemeXML -Force -Verbose | Out-Null
                                    } else {
                                        Write-Warning "Unable to patch wp.theme.themes.simple_cfg.xml, path not found"
                                    }
                                    if ((Test-Path $wpThemeDevSiteXML) -and (Test-Path $wpThemeDevSitePatchXML)) {
                                        Copy-Item $wpThemeDevSitePatchXML -Destination $wpThemeDevSiteXML -Force -Verbose | Out-Null
                                    } else {
                                        Write-Warning "Unable to patch wp.theme.themes.themedevsite_cfg.xml, path not found"
                                    }
                                }
                            }
                            Write-Verbose "Running applyCF.bat additional configuration step (Mandatory starting on WP 8.5 CF08)"
                            $wpBinDir = Join-Path ($portalConfig[[PortalConfig]::ProfilePath.ToString()]) -ChildPath "PortalServer\bin"
                            $applyCFbatch = Join-Path -Path $wpBinDir -ChildPath "applyCF.bat"
                            $wpPwd = $null
                            $wasPwd = $WebSphereAdministratorCredential.GetNetworkCredential().Password
                            if ($PortalAdministratorCredential) {
                                $wpPwd = $PortalAdministratorCredential.GetNetworkCredential().Password
                            } else {
                                $wpPwd = $wasPwd
                            }
                            if (Test-Path($applyCFbatch)) {
                                $applyProcess = $null
                                if ($SetupCredential) {
                                    $applyProcess = Invoke-Batch -BatchFile $applyCFbatch -WorkingDirectory $wpBinDir `
                                             -Arguments @("-DPortalAdminPwd=$wpPwd", "-DWasPassword=$wasPwd") `
                                             -RunAsCredential $SetupCredential -UseNewSession -Verbose
                                } else {
                                    $applyProcess = Invoke-Batch -BatchFile $applyCFbatch -WorkingDirectory $wpBinDir `
                                             -Arguments @("-DPortalAdminPwd=$wpPwd", "-DWasPassword=$wasPwd")
                                }
                                if ($applyProcess -and (!($applyProcess.StdErr)) -and ($applyProcess.ExitCode -eq 0)) {
                                    Write-Verbose "applyCF.bat ran successfully"
                                } else {
                                    $errorMsg = $null
                                    if ($applyProcess -and $applyProcess.StdErr) {
                                        $errorMsg = $applyProcess.StdErr
                                    } else {
                                        $errorMsg = $applyProcess.StdOut
                                    }
                                    $exitCode = (&{if($applyProcess) {$applyProcess.ExitCode} else {$null}})
                                    Write-Error "An error occurred while executing applyCF.bat. ExitCode: $exitCode Mesage: $errorMsg"
                                }
                            } else {
                                Write-Error "Invalid applyCF.bat file location: $applyCFbatch"
                            }
                        }
                    } else {
                        Write-Error "Portal Version not supported"
                    }
                } else {
                    Write-Error "Unable to install the CF binaries, please check IIM logs"
                }
            } else {
                Write-Error "Portal Home directory not valid: $wpHome"
            }
        } else {
            # Prior to CF 15 (WP 8.0.0.1)
            Write-Error "Portal 8.0.0.1 CF Level not supported (it should be CF15 or greater)"
        }
    } else {
        Write-Error "Only Cumulative Fixes for Portal 8.5 or Portal 8.0.0.1 are supported"
    }
    
    Return $updated
}