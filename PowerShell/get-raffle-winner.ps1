<#
.SYNOPSIS 
Performs a raffle draw of stored scans in scanning db and makes a lookup in Eventbrite to get the name.

.DESCRIPTION
Based on Sponsor value it first makes a random draw in the scanning database. When an attendee ID is return it performs a lookup using the Eventbrite API.
 
.PARAMETER SponsorCode
A string which identifies the Sponsor. The parameter is mandatory.

.PARAMETER Verbose
Using the built-in parameter -Verbose will output a textline for most commands executed.

.EXAMPLE
C:\PS> .\Get-RaffleWinner.ps1 -SponsorCode dbWatch -Verbose


.NOTES
#*================================================================================
#* Version  : 1.0
#* Created  : 07.09.2022
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
function Log-Verbose($out) { 
    $out = [System.DateTime]::Now.ToString("yyyy.MM.dd HH:mm:ss") + " ---- " + $out + "`r`n"; 
    Write-Verbose "$out"; 
}

Log-Verbose "Raffle draw for sponsor: $SponsorCode"

#Import-Module SqlServer -NoClobber

$db_server = Get-Content -Path ../secret/db_server.txt
$db_login = Get-Content -Path ../secret/db_login.txt
$db_pwd = Get-Content -Path ../secret/db_pwd.txt
$db_name = Get-Content -Path ../secret/db_name.txt

$sqlResult = Invoke-Sqlcmd -ServerInstance $db_server -Username $db_login -Password $db_pwd -Database $db_name -Query "EXEC Scan.Get_Random @EventSecret = 'e7fc1d55-b8a5-482c-9356-1fa3dc5e21e3', @ReferenceCode = '$SponsorCode'"
$ebAttendeeID = $sqlResult.ID
Log-Verbose "AttendeeID returned for $SponsorCode-raffle: $ebAttendeeID"

$ebUri = "https://www.eventbriteapi.com/v3/events/377159122087/attendees/$ebAttendeeID/"
$token = Get-Content -Path ../secret/eb_token.txt
$tokenSecure = ConvertTo-SecureString $token -AsPlainText -Force

$Response = Invoke-WebRequest -Uri $ebUri -Authentication OAuth -Token $tokenSecure -Method Get

$ebContent = $Response.Content | ConvertFrom-Json
$ebContent.profile | Select-Object name, company | Write-Host

