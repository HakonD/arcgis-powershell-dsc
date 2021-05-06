﻿Configuration SpatiotemporalBigDataStoreConfiguration
{
	param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $ServiceCredential

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ServiceCredentialIsDomainAccount = 'false'

        ,[Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SiteAdministratorCredential
        
        ,[Parameter(Mandatory=$true)]
        [System.String]
        $SpatiotemporalBigDataStoreMachineNames

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $ServerMachineNames

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $FileShareMachineName

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $DataStoreTypes = 'SpatioTemporal'
        
        ,[Parameter(Mandatory=$false)]
        [System.Int32]
        $OSDiskSize = 0

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $EnableDataDisk  

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $FileShareName = 'fileshare' 
        
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $DebugMode
    )
        
    Import-DscResource -ModuleName PSDesiredStateConfiguration 
    Import-DSCResource -ModuleName ArcGIS
	Import-DscResource -Name ArcGIS_DataStore
    Import-DscResource -Name ArcGIS_Service_Account
    Import-DscResource -name ArcGIS_WindowsService
    Import-DscResource -Name ArcGIS_xFirewall
    Import-DscResource -Name ArcGIS_xDisk
    Import-DscResource -Name ArcGIS_Disk
    
    $SpatiotemporalDataStoreHostNames = ($SpatiotemporalBigDataStoreMachineNames -split ',')    
    $ServerHostNames = ($ServerMachineNames -split ',')
    $ServerMachineName = $ServerHostNames | Select-Object -First 1    
    $IsDebugMode = $DebugMode -ieq 'true'    
    $IsServiceCredentialDomainAccount = $ServiceCredentialIsDomainAccount -ieq 'true'
    $DataStoreContentDirectory = "$($env:SystemDrive)\\arcgis\\datastore\\content"

	Node localhost
	{
        LocalConfigurationManager
        {
			ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'    
            RebootNodeIfNeeded = $true
        }
        
        if($OSDiskSize -gt 0) 
        {
            ArcGIS_Disk OSDiskSize
            {
                DriveLetter = ($env:SystemDrive -replace ":" )
                SizeInGB    = $OSDiskSize
            }
        }
        
        if($EnableDataDisk -ieq 'true')
        {
            ArcGIS_xDisk DataDisk
            {
                DiskNumber  =  2
                DriveLetter = 'F'
            }
        }

        $HasValidServiceCredential = ($ServiceCredential -and ($ServiceCredential.GetNetworkCredential().Password -ine 'Placeholder'))
        if($HasValidServiceCredential) 
        {
            if(-Not($IsServiceCredentialDomainAccount)){
                User ArcGIS_RunAsAccount
                {
                    UserName       = $ServiceCredential.UserName
                    Password       = $ServiceCredential
                    FullName       = 'ArcGIS Service Account'
                    Ensure         = 'Present'
                    PasswordChangeRequired = $false
                    PasswordNeverExpires = $true
                }
            }

            ArcGIS_WindowsService ArcGIS_DataStore_Service
            {
                Name            = 'ArcGIS Data Store'
                Credential      = $ServiceCredential
                StartupType     = 'Automatic'
                State           = 'Running' 
                DependsOn       = if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount')}else{@()}
            }
                
            ArcGIS_Service_Account DataStore_Service_Account
		    {
			    Name            = 'ArcGIS Data Store'
                RunAsAccount    = $ServiceCredential
                IsDomainAccount = $IsServiceCredentialDomainAccount
                ForceRunAsAccountUpdate = $True
			    Ensure          = 'Present'
			    DependsOn       = if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount','[ArcGIS_WindowsService]ArcGIS_DataStore_Service')}else{@('[ArcGIS_WindowsService]ArcGIS_DataStore_Service')}
                DataDir         = $DataStoreContentDirectory  
		    }

            ArcGIS_xFirewall SpatioTemporalDataStore_FirewallRules
		    {
			    Name                  = "ArcGISSpatioTemporalDataStore" 
			    DisplayName           = "ArcGIS Data Store" 
			    DisplayGroup          = "ArcGIS Data Store" 
			    Ensure                = 'Present'
			    Access                = "Allow" 
			    State                 = "Enabled" 
			    Profile               = ("Domain","Private","Public")
			    LocalPort             = ("2443", "9320", "9220")                        
			    Protocol              = "TCP" 
		    }    

            ArcGIS_DataStore SpatiotemporalDataStore
		    {
			    Ensure				= 'Present'
			    SiteAdministrator	= $SiteAdministratorCredential 
			    ServerHostName		= $ServerMachineName
			    ContentDirectory	= $DataStoreContentDirectory
                DataStoreTypes		= $DataStoreTypes
                EnableFailoverOnPrimaryStop= $true
			    DependsOn			= @('[ArcGIS_xFirewall]SpatioTemporalDataStore_FirewallRules', '[ArcGIS_Service_Account]DataStore_Service_Account') 
		    }

            foreach($ServiceToStop in @('ArcGIS Server', 'Portal for ArcGIS', 'ArcGISGeoEvent', 'ArcGISGeoEventGateway', 'ArcGIS Notebook Server', 'ArcGIS Mission Server'))
		    {
			    if(Get-Service $ServiceToStop -ErrorAction Ignore) 
			    {
				    Service "$($ServiceToStop.Replace(' ','_'))_Service"
				    {
					    Name			= $ServiceToStop
					    Credential		= $ServiceCredential
					    StartupType		= 'Manual'
					    State			= 'Stopped'
					    DependsOn		= if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount')}else{@()}
				    }
			    }
		    }
        }
	}
}