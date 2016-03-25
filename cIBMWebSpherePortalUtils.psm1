##############################################################################################################
########                                 IBM WebSphere Portal CmdLets                                #########
##############################################################################################################

enum PortalEdition {
    MP
    EXPRESS
    WCM
    EXTEND
}

##############################################################################################################
# Get-IBMWebSpherePortalVersionInfo
#   Returns a hashtable containing version information of the IBM Portal Product/Components installed
##############################################################################################################
Function Get-IBMWebSpherePortalVersionInfo() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory=$true,position=0)]
        [string]
        $InstallationDirectory
    )

    Write-Verbose "Get-IBMWebSpherePortalVersionInfo::ENTRY(InstallationDirectory=$InstallationDirectory)"
    
    #Validate Parameters
    [string] $versionInfoBat = Join-Path -Path $InstallationDirectory -ChildPath "PortalServer\bin\WPVersionInfo.bat"
    if (!(Test-Path($versionInfoBat))) {
        Write-Error "Invalid InstallationDirectory: $versionInfoBat not found"
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
    param (
        [parameter(Mandatory=$true,position=0)]
        [string]
        $InstallationDirectory
    )

    #Validate Parameters
    if (!(Test-Path($InstallationDirectory))) {
        Write-Error "Get-IBMWebSpherePortalFixesInstalled:ERROR:Parameter InstallationDirectory with value=$InstallationDirectory does not exists" -ForegroundColor DarkYellow
        Return
    }
    
    [string[]] $installedFixes = @()
    $wpver_bat = Join-Path -Path $InstallationDirectory -ChildPath "\PortalServer\bin\WPVersionInfo.bat"
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
        $wasWinSvcName = New-IBMWebSphereAppServerWindowsService -ProfilePath $wpProfileHome -ServerName $ServerName `
                            -WASEdition ND -WebSphereAdministratorCredential $WebSphereAdministratorCredential
        if ($wasWinSvcName -and (Get-Service -DisplayName $wasWinSvcName)) {
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