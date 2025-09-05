<#
.SYNOPSIS 
Exports attendee details for provided exhibitor/sponsor code from Eventbrite. Returns a unqiue list of scans and makes lookups in Eventbrite to get the attende details.

.DESCRIPTION
Based on Exhibitor/Sponsor value it returns a unique set of scanned attendee ID's from the scanning database. For each attendee ID it performs a lookup using the Eventbrite API and saves the result in an array. When completed the result is saved to a csv file.
 
.PARAMETER EventId
A string which identifies the Eventbrite EventID. The parameter is mandatory.

.PARAMETER ConfigFilePath
A string which identifies the file path to the JSON configuration file that contain database name, login details, Eventbrite API token and Event secret. The parameter is mandatory.

.PARAMETER SponsorCode
A string which identifies the Exhibitor/Sponsor. If the parameter is omitted the script will export data for all sponsors.

.PARAMETER Verbose
Using the built-in parameter -Verbose will output a textline for most commands executed.

.EXAMPLE
C:\PS> .\Export-Eventbrite-Attendee-Scans.ps1 -EventId "123456789" -ConfigFilePath ".\config.json" -SponsorCode "dbWatch" -Verbose

.EXAMPLE
C:\PS> .\Export-Eventbrite-Attendee-Scans.ps1 -EventId "123456789" -ConfigFilePath ".\config.json" -Verbose
Process all sponsors for the event

.NOTES
#*================================================================================
#* Version  : 2.0
#* Created  : 04.09.2025
#* Author   : Rune Ovlien Rakeie
#* Reqrmnts :
#* Keywords : Data Saturday, SQLSaturday, Raffle
#*================================================================================
#*================================================================================
#* REVISION HISTORY
#*================================================================================
#* Date: 12.09.2022
#* Issue: First version
#* Solution:
#*
#*================================================================================
#* Date: 04.09.2025
#* Issue: Added params for EventID and Refactored to use JSON configuration file
#* Solution: Load all configuration from JSON file instead of separate text files
#*
#*================================================================================
#>

Param
(
    # EventId
    [Parameter(Mandatory=$true,Position=1)]
    [string]$EventId,

    # ConfigFilePath
    [Parameter(Mandatory=$true,Position=2)]
    [string]$ConfigFilePath,

    # SponsorCode
    [Parameter(Mandatory=$false,Position=3)]
    [string]$SponsorCode
)
###########################################################
# SCRIPT BODY
###########################################################
function Debug-Verbose($out) { 
    $out = [System.DateTime]::Now.ToString("yyyy.MM.dd HH:mm:ss") + " ---- " + $out + "`r`n"; 
    Write-Verbose "$out"; 
}

# Load configuration from JSON file
try {
    Debug-Verbose "Loading configuration from: $ConfigFilePath"
    
    if (-not (Test-Path $ConfigFilePath)) {
        throw "Configuration file not found: $ConfigFilePath"
    }
    
    $config = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
    Debug-Verbose "Configuration loaded successfully"
}
catch {
    Write-Error "Failed to load configuration file: $($_.Exception.Message)"
    exit 1
}

# Extract configuration values
$db_server = $config.database.server
$db_login = $config.database.login
$db_pwd = $config.database.password
$db_name = $config.database.name
$event_secret = $config.event.secret
$eb_token = $config.eventbrite.token
$output_directory = $config.output.directory

# Determine if we're processing a single sponsor or all sponsors
if ([string]::IsNullOrWhiteSpace($SponsorCode)) {
    Debug-Verbose "No sponsor code provided. Will process all sponsors for the event."
    $ProcessAllSponsors = $true
} else {
    Debug-Verbose "Processing specific sponsor: $SponsorCode"
    $ProcessAllSponsors = $false
}

# Get list of sponsors to process
try {
    if ($ProcessAllSponsors) {
        Debug-Verbose "Retrieving list of all sponsors from database"
        $sponsorQuery = "EXEC Scan.Get_ReferenceCodes @EventSecret = '$event_secret'"
        $sponsorResult = Invoke-Sqlcmd -ServerInstance $db_server -Username $db_login -Password $db_pwd -Database $db_name -Query $sponsorQuery
        
        if ($sponsorResult.Count -eq 0) {
            Write-Warning "No sponsors found in database for event secret: $event_secret"
            exit 0
        }
        
        $sponsorsToProcess = $sponsorResult | ForEach-Object { $_.ReferenceCode }
        Debug-Verbose "Found $($sponsorsToProcess.Count) sponsors to process: $($sponsorsToProcess -join ', ')"
    } else {
        $sponsorsToProcess = @($SponsorCode)
        Debug-Verbose "Processing single sponsor: $SponsorCode"
    }
}
catch {
    Write-Error "Failed to retrieve sponsor list: $($_.Exception.Message)"
    exit 1
}

# Initialize Eventbrite variables
$tokenSecure = ConvertTo-SecureString $eb_token -AsPlainText -Force

# Process each sponsor
$totalProcessed = 0
$successfulExports = 0

# Get event name once (same for all sponsors)
try {
    Debug-Verbose "Retrieving event name from database"
    $eventNameQuery = "EXEC Scan.Get_EventName @EventSecret = '$event_secret'"
    $eventNameResult = Invoke-Sqlcmd -ServerInstance $db_server -Username $db_login -Password $db_pwd -Database $db_name -Query $eventNameQuery
    
    Debug-Verbose "Event name query result count: $($eventNameResult.Count)"
    
    if ($null -eq $eventNameResult -or $eventNameResult.Count -eq 0) {
        Write-Warning "No event name found for event secret: $event_secret. Using default event name."
        $eventName = "UnknownEvent"
    } else {
        $eventName = $eventNameResult[0].ToString().Trim().Replace(' ', '')  # Convert to string, trim, and remove all spaces
        if ([string]::IsNullOrWhiteSpace($eventName)) {
            Write-Warning "Event name is null or empty. Using default event name."
            $eventName = "UnknownEvent"
        } else {
            Debug-Verbose "Event name retrieved from database: $eventName"
        }
    }
}
catch {
    Write-Warning "Failed to retrieve event name: $($_.Exception.Message). Using default event name."
    $eventName = "UnknownEvent"
}

foreach ($currentSponsor in $sponsorsToProcess) {
    Debug-Verbose "Starting processing for sponsor: $currentSponsor"
    
    # Execute SQL query to get scanned attendees for current sponsor
    try {
        Debug-Verbose "Executing SQL query to get scans for sponsor: $currentSponsor"
        $sqlResult = Invoke-Sqlcmd -ServerInstance $db_server -Username $db_login -Password $db_pwd -Database $db_name -Query "EXEC Scan.Get_Scans @EventSecret = '$event_secret', @ReferenceCode = '$currentSponsor', @Unique = 1"
        Debug-Verbose "SQL query executed successfully. Found $($sqlResult.Count) records for sponsor: $currentSponsor"
        
        if ($sqlResult.Count -eq 0) {
            Write-Warning "No scan records found for sponsor: $currentSponsor"
            continue
        }
        
    }
    catch {
        Write-Error "Failed to execute SQL query for sponsor '$currentSponsor': $($_.Exception.Message)"
        continue
    }

    $AttendeeScanList = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($row in $sqlResult) {
        $AttendeeID = $row.ID
        Debug-Verbose "AttendeeID returned for $currentSponsor-raffle: $AttendeeID"

        $ebUri = "https://www.eventbriteapi.com/v3/events/$EventId/attendees/$AttendeeID/"
        
        try {
            $Response = Invoke-WebRequest -Uri $ebUri -Authentication OAuth -Token $tokenSecure -Method Get
            $WebRequestStatus = $Response.StatusCode
            Debug-Verbose "Return code from GET Web request: $WebRequestStatus"
            
            $ResponseInBytes = $Response.RawContentLength
            Debug-Verbose "Return data volume in bytes: $ResponseInBytes"
            
            $ebContent = $Response.Content | ConvertFrom-Json
            $AttendeeProfile = $ebContent.profile | Select-Object first_name, last_name, company, job_title, email

            $AttendeeScanList.Add([PSCustomObject]@{
                FirstName = $AttendeeProfile.first_name
                LastName = $AttendeeProfile.last_name
                JobTitle = $AttendeeProfile.job_title
                Company = $AttendeeProfile.company
                Email = $AttendeeProfile.email
                Note = $row.Note
            })
        }
        catch {
            Write-Warning "Failed to retrieve attendee data for ID $AttendeeID (sponsor: $currentSponsor): $($_.Exception.Message)"
            continue
        }
    }

    # Export results to CSV for current sponsor
    $SponsorTrimmed = $currentSponsor.replace(' ','')
    $EventNameTrimmed = $eventName.replace(' ','')
    $outputPath = Join-Path $output_directory "$EventNameTrimmed-$SponsorTrimmed-AttendeeScans.csv"

    try {
        # Ensure output directory exists
        $outputDir = Split-Path $outputPath -Parent
        if (-not (Test-Path $outputDir)) {
            Debug-Verbose "Output directory does not exist. Creating: $outputDir"
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            Debug-Verbose "Successfully created output directory: $outputDir"
        } else {
            Debug-Verbose "Output directory already exists: $outputDir"
        }
        
        $AttendeeScanList | Export-Csv $outputPath -NoTypeInformation
        Debug-Verbose "Results exported to: $outputPath"
        Write-Host "Successfully exported $($AttendeeScanList.Count) attendee records for sponsor '$currentSponsor' (event: '$eventName') to: $outputPath"
        $successfulExports++
    }
    catch {
        Write-Error "Failed to export CSV file for sponsor '$currentSponsor': $($_.Exception.Message)"
        continue
    }
    
    $totalProcessed++
}

# Summary
if ($ProcessAllSponsors) {
    Write-Host "`nProcessing Summary:"
    Write-Host "Total sponsors processed: $totalProcessed"
    Write-Host "Successful exports: $successfulExports"
    Write-Host "Failed exports: $($totalProcessed - $successfulExports)"
}
