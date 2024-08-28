<#
.SYNOPSIS 
Exports attendee details for provided exhibitor/sponsor code. Returns a unqiue list of scans makes lookups in Eventbrite to get the attende details.

.DESCRIPTION
Based on Exhibitor/Sponsor value it returns a unique set of scanned attendee ID's from the scanning database. For each attendee ID it performs a lookup using the Eventbrite API and saves the result in an array. When completed the result is saved to a csv file.
 
.PARAMETER SponsorCode
A string which identifies the Exhibitor/Sponsor. The parameter is mandatory.

.PARAMETER Verbose
Using the built-in parameter -Verbose will output a textline for most commands executed.

.EXAMPLE
C:\PS> .\Export-Attendee-Scans.ps1 -SponsorCode dbWatch -Verbose


.NOTES
#*================================================================================
#* Version  : 1.0
#* Created  : 12.09.2022
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
#>

Param
(
    # SponsorCode
    [Parameter(Mandatory=$true,Position=1)]
    [string]$SponsorCode
)
###########################################################
# SCRIPT BODY
###########################################################
function Debug-Verbose($out) { 
    $out = [System.DateTime]::Now.ToString("yyyy.MM.dd HH:mm:ss") + " ---- " + $out + "`r`n"; 
    Write-Verbose "$out"; 
}

Debug-Verbose "Raffle draw for sponsor: $SponsorCode"

$db_server = Get-Content -Path ../secret/db_server.txt
$db_login = Get-Content -Path ../secret/db_login.txt
$db_pwd = Get-Content -Path ../secret/db_pwd.txt
$db_name = Get-Content -Path ../secret/db_name.txt
$event_secret = Get-Content -Path ../secret/event_secret.txt

$sqlResult = Invoke-Sqlcmd -ServerInstance $db_server -Username $db_login -Password $db_pwd -Database $db_name -Query "EXEC Scan.Get_Scans @EventSecret = '$event_secret', @ReferenceCode = '$SponsorCode', @Unique = 1"



#Init Eventbrite variables
$token = Get-Content -Path ../secret/eb_token.txt
$tokenSecure = ConvertTo-SecureString $token -AsPlainText -Force

$AttendeeScanList = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($row in $sqlResult) {

    $ebAttendeeID = $row.ID
    Debug-Verbose "AttendeeID returned for $SponsorCode-raffle: $ebAttendeeID"

    $ebUri = "https://www.eventbriteapi.com/v3/events/560417723497/attendees/$ebAttendeeID/"
    
    $Response = Invoke-WebRequest -Uri $ebUri -Authentication OAuth -Token $tokenSecure -Method Get
    $WebRequestStatus = $Response.StatusCode
    Debug-Verbose "Return code form GET Web request: $WebRequestStatus"
    
    $ResponseInBytes = $Response.RawContentLength
    Debug-Verbose "Return data volume in bytes: $ResponseInBytes"
    
    $ebContent = $Response.Content | ConvertFrom-Json
    $AttendeeProfile = $ebContent.profile | Select-Object first_name, last_name, company, job_title, email

    #$AttendeeScanList.Add([PSCustomObject]@{AttendeeID=$row.ID;FirstName=$AttendeeProfile.first_name;LastName=$AttendeeProfile.last_name;JobTitle=$AttendeeProfile.job_title;Company=$AttendeeProfile.company;Email=$AttendeeProfile.email})
    $AttendeeScanList.Add([PSCustomObject]@{FirstName=$AttendeeProfile.first_name;LastName=$AttendeeProfile.last_name;JobTitle=$AttendeeProfile.job_title;Company=$AttendeeProfile.company;Email=$AttendeeProfile.email})
}

$SponsorTrimmed = $SponsorCode.replace(' ','')
$AttendeeScanList | Export-Csv "../AttendeeScanLists/DataSatOslo2023-$SponsorTrimmed-AttendeeScans.csv" -NoTypeInformation #-UseQuotes AsNeeded

