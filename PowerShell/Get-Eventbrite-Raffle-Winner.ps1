<#
.SYNOPSIS 
Performs a raffle draw of stored scans in scanning database and retrieves winner details from Eventbrite.

.DESCRIPTION
Performs a random draw from the scanning database for a specific sponsor/exhibitor. When an attendee ID is returned, 
it performs a lookup using the Eventbrite API to get the full attendee profile information including name, email, 
company, and job title. This is typically used for end-of-day prize drawings at conferences.
 
.PARAMETER EventId
A string which identifies the Eventbrite EventID. The parameter is mandatory.

.PARAMETER ConfigFilePath
A string which identifies the file path to the JSON configuration file that contains database name, login details, 
Eventbrite API token and Event secret. The parameter is mandatory.

.PARAMETER SponsorCode
A string which identifies the Sponsor/Exhibitor for the raffle draw. The parameter is mandatory.

.PARAMETER Verbose
Using the built-in parameter -Verbose will output a textline for most commands executed.

.EXAMPLE
C:\PS> .\Get-RaffleWinner.ps1 -SponsorCode dbWatch -Verbose


.NOTES
#*================================================================================
#* Version  : 2.0
#* Created  : 05.09.2025
#* Author   : Rune Ovlien Rakeie
#* Reqrmnts :
#* Keywords : Data Saturday, SQLSaturday, Raffle
#*================================================================================
#*================================================================================
#* REVISION HISTORY
#*================================================================================
#* Date: 07.09.2022
#* Issue: First version
#* Solution:
#*
#*================================================================================
#*================================================================================
#* Date: 05.09.2025
#* Issue: Added params for EventID and Refactored to use JSON configuration file
#* Solution: Load all configuration from JSON file instead of separate text files
#*
#*================================================================================
#>

Param
(
    # EventId
    [Parameter(Mandatory=$true, Position=1, HelpMessage="The Eventbrite Event ID")]
    [ValidateNotNullOrEmpty()]
    [string]$EventId,

    # ConfigFilePath
    [Parameter(Mandatory=$true, Position=2, HelpMessage="Path to the JSON configuration file")]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$ConfigFilePath,
    
    # SponsorCode
    [Parameter(Mandatory=$true, Position=3, HelpMessage="The Sponsor/Exhibitor code for the raffle")]
    [ValidateNotNullOrEmpty()]
    [string]$SponsorCode
)
###########################################################
# SCRIPT BODY
###########################################################
function Debug-Verbose($out) { 
    $out = [System.DateTime]::Now.ToString("yyyy.MM.dd HH:mm:ss") + " ---- " + $out + "`r`n"; 
    Write-Verbose "$out"; 
}

# Function to display winner in formatted output
function Show-Winner {
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$Company,
        [string]$JobTitle,
        [string]$SponsorCode
    )
    
    $fullName = "$FirstName $LastName".Trim()

    $title = "🎉 RAFFLE WINNER SELECTED FOR SPONSOR $SponsorCode! 🎉"
    Write-Host ""
    Write-Host $title -ForegroundColor Yellow -BackgroundColor DarkBlue -NoNewline
    Write-Host ""  # This forces a newline without background color
    Write-Host "================================" -ForegroundColor Yellow
    Write-Host "Winner: " -NoNewline -ForegroundColor Cyan
    Write-Host $fullName -ForegroundColor White
    
    if (-not [string]::IsNullOrWhiteSpace($Company)) {
        Write-Host "Company: " -NoNewline -ForegroundColor Cyan
        Write-Host $Company -ForegroundColor White
    }
    
    if (-not [string]::IsNullOrWhiteSpace($JobTitle)) {
        Write-Host "Job Title: " -NoNewline -ForegroundColor Cyan
        Write-Host $JobTitle -ForegroundColor White
    }
    
    Write-Host "Draw Time: " -NoNewline -ForegroundColor Cyan
    Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor White
    Write-Host "================================" -ForegroundColor Yellow
}

try {
    Debug-Verbose "Starting raffle draw for sponsor: $SponsorCode"

    # Load configuration from JSON file
    try {
        Debug-Verbose "Loading configuration from: $ConfigFilePath"
        
        $config = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
        Debug-Verbose "Configuration loaded successfully"
    }
    catch {
        Write-Error "Failed to load configuration file: $($_.Exception.Message)"
        exit 1
    }

    # Extract and validate configuration values
    $requiredConfigKeys = @("database.server", "database.login", "database.password", "database.name", "event.secret", "eventbrite.token")
    foreach ($key in $requiredConfigKeys) {
        $keyParts = $key.Split('.')
        $value = $config
        foreach ($part in $keyParts) {
            $value = $value.$part
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Missing or empty configuration value for: $key"
        }
    }

    $db_server = $config.database.server
    $db_login = $config.database.login
    $db_pwd = $config.database.password
    $db_name = $config.database.name
    $event_secret = $config.event.secret
    $eb_token = $config.eventbrite.token

    Debug-Verbose "Configuration validated successfully"

    # Perform raffle draw
    Debug-Verbose "Executing raffle query for sponsor: $SponsorCode"
    
    try {
        $sqlResult = Invoke-Sqlcmd -ServerInstance $db_server -Username $db_login -Password $db_pwd -Database $db_name -Query "EXEC Scan.Get_Random @EventSecret = '$event_secret', @ReferenceCode = '$SponsorCode'" -ErrorAction Stop
        
        if ($null -eq $sqlResult -or $sqlResult.Count -eq 0) {
            Write-Warning "No attendees have been scanned yet by sponsor: $SponsorCode"
            exit 0
        }
        
        $ebAttendeeID = $sqlResult.ID
        Debug-Verbose "Random attendee selected - ID: $ebAttendeeID"
    }
    catch {
        Write-Error "Failed to execute raffle query: $($_.Exception.Message)"
        exit 1
    }

    # Retrieve attendee details from Eventbrite
    Debug-Verbose "Retrieving attendee details from Eventbrite API"
    
    try {
        $ebUri = "https://www.eventbriteapi.com/v3/events/$EventId/attendees/$ebAttendeeID/"
        $tokenSecure = ConvertTo-SecureString $eb_token -AsPlainText -Force
        
        $Response = Invoke-WebRequest -Uri $ebUri -Authentication OAuth -Token $tokenSecure -Method Get -ErrorAction Stop
        Debug-Verbose "Eventbrite API request completed successfully"
        
        $WebRequestStatus = $Response.StatusCode
        Debug-Verbose "HTTP Response Code: $WebRequestStatus"
        
        $ResponseInBytes = $Response.RawContentLength
        Debug-Verbose "Response data volume: $ResponseInBytes bytes"
        
        $ebContent = $Response.Content | ConvertFrom-Json
        $ebprofile = $ebContent.profile
        
        # Display winner information
        Show-Winner -FirstName $ebprofile.first_name -LastName $ebprofile.last_name -Company $ebprofile.company -JobTitle $ebprofile.job_title -AttendeeId $ebAttendeeID -SponsorCode $SponsorCode
        
        Debug-Verbose "Raffle completed successfully for sponsor: $SponsorCode"
    }
    catch {
        Write-Error "Failed to retrieve attendee details from Eventbrite: $($_.Exception.Message)"
        Write-Host "Selected Attendee ID: $ebAttendeeID" -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Error "Unexpected error occurred: $($_.Exception.Message)"
    exit 1
}