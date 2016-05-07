# Import IBM WebSphere Portal Utils Module
Import-Module $PSScriptRoot\cIBMWebSpherePortalUtils.psm1 -ErrorAction Stop

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

enum LDAPType {
    AD
    IDS
    DOMINO
    NOVELL
    SUNONE
}

##############################################################################################################
# Register-LDAPRepository
#   Initializes a new LDAP config file to assist in executing the LDAP configuration
#   Returns the path to the helper file
##############################################################################################################
Function Register-LDAPRepository() {
    param (
        [parameter(Mandatory = $true)]
        [String] $LDAPID,
        
        [parameter(Mandatory = $true)]
        [String] $RealmName,

        [LDAPType] $LDAPType = [LDAPType]::AD,

        [parameter(Mandatory = $true)]
        [String] $LDAPHostName,

        [Int] $LDAPPort = 389,
        
        [String] $BaseDN,

        [String] $UserSearchBase,

        [String] $GroupSearchBase,
        
        [Hashtable] $UserAttributesConfig,

        [Hashtable] $GroupAttributesConfig,

        [parameter(Mandatory = $true)]
        [String] $BindDN,

        [parameter(Mandatory = $true)]
        [PSCredential] $BindPassword,

        [parameter(Mandatory = $true)]
        [PSCredential] $WebSphereAdministratorCredential
    )
    [bool] $buildSuccessfull = $false
    $portalConfig = Get-IBMPortalConfig
    $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
    $wpServerName = $portalConfig[[PortalConfig]::ServerName.ToString()]
    
    $ldapConfigFile = Initialize-LDAPConfig `
                        -LDAPID $LDAPID `
                        -LDAPType $LDAPType `
                        -LDAPHostName $LDAPHostName `
                        -LDAPPort $LDAPPort `
                        -BaseDN $BaseDN `
                        -UserSearchBase $UserSearchBase `
                        -GroupSearchBase $GroupSearchBase `
                        -BindDN $BindDN `
                        -BindPassword $BindPassword `
                        -WebSphereAdministratorCredential $WebSphereAdministratorCredential
    
    if (($ldapConfigFile) -and (Test-Path($ldapConfigFile))) {
        #Ensure Portal server is started for standalone servers
        Start-WebSpherePortal $wpServerName -WebSphereAdministratorCredential $WebSphereAdministratorCredential

        Write-Verbose "Validating LDAP Configuration"
        $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Task "validate-federated-ldap -DparentProperties=$ldapConfigFile" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
        $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
        if ($buildSuccessfull) {
            Write-Verbose "Applying LDAP Configuration"
            $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Task "wp-create-ldap" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
            $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
            if ($buildSuccessfull) {
                Write-Verbose "Validating LDAP Attribute Configuration"
                $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Task "wp-validate-federated-ldap-attribute-config" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
                if ($buildSuccessfull) {
                    #Restart Portal
                    Stop-WebSpherePortal $wpServerName -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                    Start-WebSpherePortal $wpServerName -WebSphereAdministratorCredential $WebSphereAdministratorCredential

                    #Retrieves the current realm name
                    $currentRealmName = Get-RealmName -ProfileConfigEngineDirectory $cfgEnginePath

                    #Initialize realm configuration and check to see if it exists
                    $realmInitialized = Initialize-SecurityRealm `
                                        -RealmName $RealmName `
                                        -BaseDN $BaseDN `
                                        -WebSphereAdministratorCredential $WebSphereAdministratorCredential

                    if ($realmInitialized) {
                        if (($currentRealmName -ne $null) -and ($RealmName -eq $currentRealmName)) {
                            Write-Verbose "Realm already exists, adding LDAP as an entry"
                            $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Task "wp-add-realm-baseentry" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                            $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
                        } else {
                            Write-Verbose "Creating new security realm and adding LDAP as an entry"
                            $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Task "wp-create-realm" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                            $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
                            if ($buildSuccessfull) {
                                Write-Verbose "Adding default file-based reposistory as an entry"
                                $cfgEngineProc = Invoke-ConfigEngine `
                                                    -Path $cfgEnginePath `
                                                    -Task @("wp-add-realm-baseentry", "-DrealmName=$RealmName", "-DaddBaseEntry=o=defaultWIMFileBasedRealm") `
                                                    -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                                $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
                            }
                        }
                        if ($buildSuccessfull) {
                            Write-Verbose "LDAP Configured Succesfully, Restarting Portal"
                            #Restart Portal
                            Stop-WebSpherePortal $wpServerName -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                            Start-WebSpherePortal $wpServerName -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                        } else {
                            Write-Error "An error occurred while creating/adding the security realm"
                        }
                    } else {
                        Write-Error "An error occurred while initializing the security realm"
                    }
                } else {
                    Write-Error "An error occurred while validating LDAP attribute configuration"
                }
            } else {
                Write-Error "An error occurred while creating LDAP config"
            }
        } else {
            Write-Error "An error occurred while validating LDAP configuration, please check $ldapConfigFile"
        }
    }

    Return $buildSuccessfull
}

##############################################################################################################
# Initialize-LDAPConfig
#   Initializes a new LDAP config file to assist in executing the LDAP configuration
#   Returns the path to the helper file
##############################################################################################################
Function Initialize-LDAPConfig() {
    param (
        [parameter(Mandatory = $true)]
        [String] $LDAPID,

        [LDAPType] $LDAPType = [LDAPType]::AD,

        [parameter(Mandatory = $true)]
        [String] $LDAPHostName,

        [Int] $LDAPPort = 389,
        
        [String] $BaseDN,

        [String] $UserSearchBase,

        [String] $GroupSearchBase,

        [parameter(Mandatory = $true)]
        [String] $BindDN,

        [parameter(Mandatory = $true)]
        [PSCredential] $BindPassword,

        [parameter(Mandatory = $true)]
        [PSCredential] $WebSphereAdministratorCredential
    )

    $portalConfig = Get-IBMPortalConfig
    $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
    
    $wp_add_federated_file = $null

    switch ($LDAPType) {
        AD { $wp_add_federated_file = "wp_add_federated_ad.properties"}
        IDS { $wp_add_federated_file = "wp_add_federated_ids.properties"}
        DOMINO { $wp_add_federated_file = "wp_add_federated_domino.properties"}
        NOVELL { $wp_add_federated_file = "wp_add_federated_novell.properties"}
        SUNONE { $wp_add_federated_file = "wp_add_federated_sunone.properties"}
        default { Write-Error "Invalid LDAP Type" }
    }

    $ldapConfigBaseFile = Join-Path -Path $cfgEnginePath -ChildPath "config\helpers\$wp_add_federated_file"
    $ldapConfigNewFile = Join-Path -Path $cfgEnginePath -ChildPath "$LDAPID`_$wp_add_federated_file"

    if (!(Test-Path($ldapConfigBaseFile))) {
        Write-Error "Unable to locate wp_add_federated_*.properties"
        Return $false
    }

    # Copy Helper File into new Location
    Copy-Item -Path $ldapConfigBaseFile -Destination $ldapConfigNewFile | Out-Null

    [hashtable] $ldapprops = @{}
    [hashtable] $adminProps = @{}

    $ldapprops.Add("federated.ldap.id", $LDAPID)
    $ldapprops.Add("federated.ldap.host", $LDAPHostName)
    $ldapprops.Add("federated.ldap.port", $LDAPPort)
    $ldapprops.Add("federated.ldap.bindDN", $BindDN)
    $ldapprops.Add("federated.ldap.bindPassword", $BindPassword.GetNetworkCredential().Password)
    $ldapprops.Add("federated.ldap.ldapServerType", $LDAPType)
    $ldapprops.Add("federated.ldap.baseDN", $BaseDN)

    $ldapprops.Add("federated.ldap.et.group.searchBases", $GroupSearchBase)
    $ldapprops.Add("federated.ldap.et.personaccount.searchBases", $UserSearchBase)

    if ($LDAPType -eq [LDAPType]::AD) {
        $ldapprops.Add("federated.ldap.et.group.searchFilter", $null)
        $ldapprops.Add("federated.ldap.et.group.objectClasses", "group")
        $ldapprops.Add("federated.ldap.et.group.objectClassesForCreate", $null)

        $ldapprops.Add("federated.ldap.et.personaccount.searchFilter", $null)
        $ldapprops.Add("federated.ldap.et.personaccount.objectClasses", "user")
        $ldapprops.Add("federated.ldap.et.personaccount.objectClassesForCreate", $null)

        $ldapprops.Add("federated.ldap.gm.groupMemberName", "member")
        $ldapprops.Add("federated.ldap.gm.objectClass", "group")
        $ldapprops.Add("federated.ldap.gm.scope", "direct")
        $ldapprops.Add("federated.ldap.gm.dummyMember", $null)
    }

    Set-JavaProperties $ldapConfigNewFile $ldapprops

    Return $ldapConfigNewFile 
}

##############################################################################################################
# Get-PortalUserRepositories
#   Returns a list of repositories configured for portal
##############################################################################################################
Function Get-PortalUserRepositories() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param ([PSCredential] $WebSphereAdministratorCredential)
    $portalConfig = Get-IBMPortalConfig
    $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
    $LDAPIDs = @()
    
    $REPOSITORY_QUERY_FILTER = "[wplc-query-federated-repository]"
    $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath `
                                         -Task "wp-query-repository" `
                                         -OutputFilter $REPOSITORY_QUERY_FILTER `
                                         -WebSphereAdministratorCredential $WebSphereAdministratorCredential
    if ($cfgEngineProc -and ($cfgEngineProc.StdOut -ne $null) -and ($cfgEngineProc.StdOut.GetType() -eq [Object[]])) {
        $fedRepos = $false
        $startParsing = $false
        foreach ($str in $cfgEngineProc.StdOut) {
            if ($str.StartsWith($REPOSITORY_QUERY_FILTER + " Existing Federated Repositories")) {
                $fedRepos = $true
            } elseif ($fedRepos -and ($str.StartsWith($REPOSITORY_QUERY_FILTER + " *****************"))) {
                $startParsing = $true
            } elseif ($fedRepos -and $startParsing) {
                $repoInfoIdx = $str.IndexOf(" : {", $REPOSITORY_QUERY_FILTER.Length)
                if ($str.StartsWith($REPOSITORY_QUERY_FILTER + " *****************")) {
                    $startParsing = $false
                } elseif ($str.StartsWith($REPOSITORY_QUERY_FILTER) -and ($repoInfoIdx -gt 0)) {
                    $LDAPIDs += ($str.Substring($REPOSITORY_QUERY_FILTER.Length+1, ($repoInfoIdx - $REPOSITORY_QUERY_FILTER.Length - 1)))
                }
            }
        }
    }

    Return $LDAPIDs
}

##############################################################################################################
# Get-RealmName
#   Returns the name of the current realm
##############################################################################################################
Function Get-RealmName() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param ([PSCredential] $WebSphereAdministratorCredential)
    $portalConfig = Get-IBMPortalConfig
    $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
    
    [string] $REALM_QUERY_FILTER = "[wplc-query-realm-baseentry]"
    [string] $RetRealmName = $null
    $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath `
                                         -Task "wp-query-realm-baseentry" `
                                         -OutputFilter $REALM_QUERY_FILTER `
                                         -WebSphereAdministratorCredential $WebSphereAdministratorCredential
    if ($cfgEngineProc -and ($cfgEngineProc.StdOut -ne $null) -and ($cfgEngineProc.StdOut.GetType() -eq [String[]])) {
        foreach ($str in $cfgEngineProc.StdOut) {
            [string] $realmPrefix = "$REALM_QUERY_FILTER Base entries for realm "
            if (([string]$str).StartsWith($realmPrefix)) {
                $RetRealmName = ([string]$str).Substring($realmPrefix.Length, ([string]$str).IndexOf(' ', $realmPrefix.Length) - $realmPrefix.Length)
            }
        }
    }

    Return $RetRealmName
}

##############################################################################################################
# Initialize-SecurityRealm
#   Initializes wkplc.properties variables to create a realm
##############################################################################################################
Function Initialize-SecurityRealm() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory = $true)]
        [String] $RealmName,

        [String] $BaseDN,

        [parameter(Mandatory = $true)]
        [PSCredential] $WebSphereAdministratorCredential
    )

    $portalConfig = Get-IBMPortalConfig
    $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
    
    $wpConfigPropertiesFile = Join-Path -Path $cfgEnginePath -ChildPath "properties\wkplc.properties"

    if (!(Test-Path($wpConfigPropertiesFile))) {
        Write-Error "Unable to locate wkplc.properties"
        Return $false
    }

    # Backup Files
    Copy-Item -Path $wpConfigPropertiesFile -Destination "$wpConfigPropertiesFile.bak.$(get-date -f yyyyMMddHHmmss)"

    [hashtable] $realmprops = @{}
    $realmprops.Add("realmName", $RealmName)
    $realmprops.Add("addBaseEntry", $BaseDN)
    $realmprops.Add("securityUse", "active")
    $realmprops.Add("delimiter", "/")

    $realmprops.Add("WasPassword",$WebSphereAdministratorCredential.GetNetworkCredential().Password)

    Set-JavaProperties $wpConfigPropertiesFile $realmprops

    Return $true
}