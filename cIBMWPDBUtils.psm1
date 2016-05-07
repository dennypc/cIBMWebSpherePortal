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

enum DatabaseType {
    SQLSERVER
    DB2
    ORACLE
    DERBY
}

$DatabaseTypeMap = @{
    ([DatabaseType]::SQLSERVER.ToString()) = "sqlserver2005";
    ([DatabaseType]::DB2.ToString()) = "db2";
    ([DatabaseType]::ORACLE.ToString()) = "oracle";
    ([DatabaseType]::DERBY.ToString()) = "derby"
}

##############################################################################################################
# Initialize-PortalDatabaseTransfer
#   Initializes the wkplc property files in order to perform the database transfer
##############################################################################################################
Function Initialize-PortalDatabaseTransfer() {
    param (
        [parameter(Mandatory = $false)]
        [DatabaseType] $PortalDatabaseType = [DatabaseType]::SQLSERVER,

        [parameter(Mandatory = $true)]
        [String] $DatabaseHostName,

        [parameter(Mandatory = $false)]
        [String] $DatabaseInstanceName,

        [parameter(Mandatory = $true)]
        [Int] $DatabasePort = 1433,

        [parameter(Mandatory = $false)]
        [String] $DatabaseInstanceHomeDirectory,

        [parameter(Mandatory = $true)]
        [hashtable] $PortalDBConfig,

        [parameter(Mandatory = $true)]
        [String] $JDBCDriverPath,
        
        [parameter(Mandatory = $false)]
        [PSCredential] $DBACredential,

        [parameter(Mandatory = $true)]
        [PSCredential] $WebSphereAdministratorCredential,
        
        [parameter(Mandatory=$true)]
        [PSCredential] $RelDBCredential,
        
        [bool] $SameDBCredentials = $true,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $CommDBCredential,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $CustDBCredential,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $JcrDBCredential,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $LmDBCredential,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $FdbkDBCredential
    )

    $portalConfig = Get-IBMPortalConfig
    $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]

    $wpConfigPropertiesFile = Join-Path $cfgEnginePath "properties\wkplc.properties"
    $wpdbdomainPropertiesFile = Join-Path $cfgEnginePath "properties\wkplc_dbdomain.properties"
    $wpdbtypePropertiesFile = Join-Path $cfgEnginePath "properties\wkplc_dbtype.properties"

    if ((!(Test-Path($wpdbdomainPropertiesFile))) -or (!(Test-Path($wpdbtypePropertiesFile))) -or (!(Test-Path($wpConfigPropertiesFile)))) {
        Write-Error "Unable to locate wkplc_dbdomain or wkplc_dbtype propertie files"
        Return $false
    }

    # Backup Files
    Write-Verbose "Backing up property files for database transfer"
    $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Tasks "backup-property-files-for-dbxfer" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
    if (!($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))) {
        Write-Error "Unable to backup files"
        Return $false
    }

    [hashtable] $dbdomainprops = @{}
    [hashtable] $dbtypeprops = @{}

    Foreach ($dbDomain in $PortalDBConfig.DbDomains) {
        $dbDomainName = $dbDomain.DomainName
        $dbdomainprops.Add("$dbDomainName.DbType", $DatabaseTypeMap[$PortalDatabaseType.ToString()])
        
        # Set Global DB Configuration
        if ($PortalDatabaseType -eq [DatabaseType]::SQLSERVER) {
            $baseSQLServerURL = "jdbc:sqlserver://$DatabaseHostName`:$DatabasePort"
            if ($DatabaseInstanceName) {
                $baseSQLServerURL = $baseSQLServerURL + ";instanceName=$DatabaseInstanceName"
            }
            $dbURL = $baseSQLServerURL + ";SelectMethod=cursor;DatabaseName=" + $dbDomain.DatabaseName
            $dbdomainprops.Add("$dbDomainName.DbUrl", $dbURL)
            $dbdomainprops.Add("$dbDomainName.AdminUrl", $baseSQLServerURL)
            $dbdomainprops.Add("$dbDomainName.DbHostName", $DatabaseHostName)

            # Setup DbHome for SQL Server
            if ($DatabaseInstanceHomeDirectory) {
                $dbdomainprops.Add("$dbDomainName.DbHome", ($DatabaseInstanceHomeDirectory -replace "\\","\\"))
            }
        } else {
            #TODO: Add support for other database types
            Write-Error "Database type not supported"
        }

        if ($DBACredential) {
            $dbdomainprops.Add("$dbDomainName.DBA.DbUser", $DBACredential.UserName)
            $dbdomainprops.Add("$dbDomainName.DBA.DbPassword", $DBACredential.GetNetworkCredential().Password)
        }
        
        # Set Database-Specific Config
        if ($SameDBCredentials) {
            $dbdomainprops.Add("$dbDomainName.DbUser", $RelDBCredential.UserName)
            $dbdomainprops.Add("$dbDomainName.DbPassword", $RelDBCredential.GetNetworkCredential().Password)
        }

        $dbdomainprops.Add("$dbDomainName.DbName", $dbDomain.DatabaseName)
        $dbdomainprops.Add("$dbDomainName.DbSchema", $dbDomain.Schema)
        $dbdomainprops.Add("$dbDomainName.DataSourceName", $dbDomain.DataSourceName)
    }
    
    if (!($SameDBCredentials)) {
        $dbdomainprops.Add("release.DbUser", $RelDBCredential.UserName)
        $dbdomainprops.Add("release.DbPassword", $RelDBCredential.GetNetworkCredential().Password)
        $dbdomainprops.Add("community.DbUser", $CommDBCredential.UserName)
        $dbdomainprops.Add("community.DbPassword", $CommDBCredential.GetNetworkCredential().Password)
        $dbdomainprops.Add("customization.DbUser", $CustDBCredential.UserName)
        $dbdomainprops.Add("customization.DbPassword", $CustDBCredential.GetNetworkCredential().Password)
        $dbdomainprops.Add("jcr.DbUser", $JcrDBCredential.UserName)
        $dbdomainprops.Add("jcr.DbPassword", $JcrDBCredential.GetNetworkCredential().Password)
        $dbdomainprops.Add("likeminds.DbUser", $LmDBCredential.UserName)
        $dbdomainprops.Add("likeminds.DbPassword", $LmDBCredential.GetNetworkCredential().Password)
        $dbdomainprops.Add("feedback.DbUser", $FdbkDBCredential.UserName)
        $dbdomainprops.Add("feedback.DbPassword", $FdbkDBCredential.GetNetworkCredential().Password)
    }

    if ($PortalDatabaseType -eq [DatabaseType]::SQLSERVER) {
        $dbtypeprops.Add("sqlserver2005.DbLibrary", ($JDBCDriverPath -replace "\\","/"))
    } else {
        #TODO: Add support for other database types
        Return $false
    }

    # Update Property Files
    Set-JavaProperties $wpdbdomainPropertiesFile $dbdomainprops
    Set-JavaProperties $wpdbtypePropertiesFile $dbtypeprops

    Return $true
}

##############################################################################################################
# Invoke-DatabaseTransfer
#   Performs a database transfer from derby to the target database specified
##############################################################################################################
Function Invoke-DatabaseTransfer {
	[CmdletBinding()]
	param (
        [parameter(Mandatory = $true)]
        [DatabaseType] $PortalDatabaseType = [DatabaseType]::SQLSERVER,
        
        [parameter(Mandatory = $true)]
		[String] $DatabaseHostName,

		[String] $DatabaseInstanceHomeDirectory,

		[parameter(Mandatory = $true)]
        [hashtable] $PortalDBConfig,

		[String] $DatabaseInstanceName,

		[parameter(Mandatory = $true)]
		[Int] $DatabasePort,
        
        [String] $JDBCDriverPath,
        
        [parameter(Mandatory = $false)]
        [PSCredential] $DBACredential,

        [parameter(Mandatory = $true)]
        [PSCredential] $WebSphereAdministratorCredential,
        
        [parameter(Mandatory=$true)]
        [PSCredential] $RelDBCredential,
        
        [bool] $SameDBCredentials = $true,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $CommDBCredential,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $CustDBCredential,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $JcrDBCredential,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $LmDBCredential,
        
        [parameter(Mandatory=$false)]
        [PSCredential] $FdbkDBCredential
	)
    
    $portalConfig = Get-IBMPortalConfig
    $cfgEnginePath = $portalConfig[[PortalConfig]::ProfileConfigEnginePath.ToString()]
    
    # Initialize the database transfer
    $initialized = Initialize-PortalDatabaseTransfer @psboundparameters

    if ($initialized) {
        Stop-WebSpherePortal -WebSphereAdministratorCredential $WebSphereAdministratorCredential

        # Create Database
        Write-Verbose "Creating Databases"
        $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Tasks "create-database" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
        $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
        if ($buildSuccessfull) {
            # Setup Database
            Write-Verbose "Setting up Databases/Users/Schema"
            $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Tasks "setup-database" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
            $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
            if ($buildSuccessfull) {
                # Validate Database
                Write-Verbose "Validate Databases"
                $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Tasks @("validate-database","validate-database-environment") -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
                if ($buildSuccessfull) {
                    Stop-WebSpherePortal -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                    # Transfer Database
                    Write-Verbose "Tranferring Databases"
                    sleep -s 10
                    $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Tasks @("database-transfer","enable-profiles-check-managed","package-profiles") -WebSphereAdministratorCredential $WebSphereAdministratorCredential -Verbose
                    $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
                    if ($buildSuccessfull) {
                        # Grant Privileges
                        Write-Verbose "Granting Runtime DB User Privileges"
                        $cfgEngineProc = Invoke-ConfigEngine -Path $cfgEnginePath -Tasks "grant-runtime-db-user-privileges" -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                        $buildSuccessfull = ($cfgEngineProc -and ($cfgEngineProc.ExitCode -eq 0))
                        if ($buildSuccessfull) {
                            Write-Verbose "IBM WebSphere Portal Database Transfer SUCCESSFUL. Restarting."
                            Stop-WebSpherePortal -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                            Start-WebSpherePortal -WebSphereAdministratorCredential $WebSphereAdministratorCredential
                        } else {
                            Write-Verbose ($cfgEngineProc.StdOut)
                            Write-Error "IBM WebSphere Portal Database Transfer FAILED:: An error occurred while granting user privileges"
                        }
                    } else {
                        Write-Verbose "IBM WebSphere Portal Database Transfer FAILED:: An error occurred while transferring the database"
                        Write-Error "IBM WebSphere Portal Database Transfer FAILED:: An error occurred while transferring the database"
                    }
                } else {
                    Write-Verbose ($cfgEngineProc.StdOut)
                    Write-Error "IBM WebSphere Portal Database Transfer FAILED:: An error occurred while validating the databases"
                }
            } else {
                Write-Verbose ($cfgEngineProc.StdOut)
                Write-Error "IBM WebSphere Portal Database Transfer FAILED:: An error occurred while setting up the databases"
            }
        } else {
            Write-Verbose ($cfgEngineProc.StdOut)
            Write-Error "IBM WebSphere Portal Database Transfer FAILED:: An error occurred while creating the databases"
        }
    } else {
        Write-Error "IBM WebSphere Portal Database Transfer FAILED:: unable to initialize properly"
    }
}