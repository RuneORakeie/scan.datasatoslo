# scan.datasatsto.se
A QR code scanning and reporting API for SQL/Data Saturday conferences

# What is it?

Back in the day when we used to have SQL Saturdays, attendees would have QR codes that they could scan
in exhibitor booths. Event organizers could download a database extract from the SQL Saturday site with all
scans, and send that extract to each respective exhibitor.

This is a framework to:
- Create QR codes as PNG files, as well as inline HTML data objects
- Register when a QR code is scanned
- Associate a terminal (QR code scanner/smart phone) to a specific exhibitor
- Create a report of all scanned QR codes for an event
- Purge data for expired events

## Privacy

The solution works with integer identities, so it does not contain any personally identifiable information.
This means that you'll have to connect those IDs to your attendee records yourself, or use the Eventbrite
integration to automatically retrieve attendee details.

No IP addresses, locations, etc, are used or checked or stored, unless specifically entered in the note
field by vendors.

The solution does not use passwords, with the exception of the EventSecret, which the event owner will need to
extract reporting data if they don't have database access.

# Setup

You'll need:
- A web server that runs NodeJS, for example IIS or Azure WebApps (recommended).
- A SQL Server instance, any edition.

If you are using Eventbrite as your ticketing platform you also need:
- Create an API key (found under your Eventbrite Account settings/Developer Links/API Keys)
- It is the "Private token" valkue in your API Key you will use for authentication when querying the Eventbrite API 
- Create configuration file for export scripts (see Eventbrite integration section below)

To set up:
- Deploy the Git repository in the web root.
- You may have to use npm to install all of the dependencies. An Azure Web App does this for you.
- Run the database deployment script in a blank SQL Server database. The entire solution runs in its own
  schema, so it will probably play nice with other apps if you need to.
- Create a user to the SQL Server database. It can be a contained user (without login) if you want.
- GRANT EXECUTE ON SCHEMA::Scan TO {database user};
- Set up environment variables for the web app

Environment variables:

- cookieSecret: Used to encrypt cookies. Not required, but recommended.
- dbserver: Fully qualified name of the database instance
- dbname: Database name
- dblogin: Login name
- dbpassword: Password

**Note** The app currently only supports SQL Authentication.

# Eventbrite Integration
- Integrate with Eventbrite to retrieve full attendee details for raffle drawing
- Export attendee scan data into csv format with attendee profile information for sharing with your sponsors. Data shared is first name, lastname, job title, company name and email address.

To setup, you additionally need to run the following SQL scripts in you database:
- Get_EventName.sql
- Get_ReferenceCodes.sql

## Configuration File

Create a JSON configuration file for the export scripts:

```json
{
    "database": {
        "server": "your-db-server-name",
        "name": "your-database-name", 
        "login": "your-db-username",
        "password": "your-db-password"
    },
    "eventbrite": {
        "token": "your-eventbrite-oauth-token"
    },
    "event": {
        "secret": "your-event-secret"
    },
    "output": {
        "directory": "../AttendeeScanLists/"
    }
}
```

## Export Scripts

### Export-Attendee-Scans.ps1

PowerShell script that exports attendee scan data with full Eventbrite profile information.

**Parameters:**
- `EventId` (mandatory): The Eventbrite Event ID
- `ConfigFilePath` (mandatory): Path to the JSON configuration file
- `SponsorCode` (optional): Specific exhibitor/sponsor code. If omitted, all sponsors are processed

**Examples:**
```powershell
# Export scans for a specific sponsor
.\Export-Attendee-Scans.ps1 -EventId "123456789" -ConfigFilePath ".\config.json" -SponsorCode "Microsoft" -Verbose

# Export scans for all sponsors
.\Export-Attendee-Scans.ps1 -EventId "123456789" -ConfigFilePath ".\config.json" -Verbose
```

**Features:**
- Retrieves unique scanned attendee IDs from the scanning database
- Looks up full attendee details from Eventbrite API (name, email, company, job title)
- Dynamically uses event name from database (spaces removed for filename)
- Creates output directory if it doesn't exist
- Exports to CSV format: `{EventName}-{SponsorCode}-AttendeeScans.csv`
- Processes all sponsors when SponsorCode is omitted
- Comprehensive error handling and verbose logging
- Processing summary when handling multiple sponsors

**Required Database Stored Procedures:**
- `Scan.Get_Scans`: Retrieves scanned attendee data
- `Scan.Get_Sponsors`: Returns list of all sponsors for an event (used when processing all sponsors)

**Output CSV Columns:**
- FirstName
- LastName  
- JobTitle
- Company
- Email
- Note (from scan database)

# API Reference

Here's how the scanning flow works.

![Sample Mailchimp integration](https://raw.githubusercontent.com/strdco/scan.datasatsto.se/boss/Documentation/scanning-flow.png)

### With cookie-enabled terminal:

* An exhibitor will first go to `/setup` to create and store an exhibitor code. This code is stored as a cookie
  on the browser, so the process needs to be completed for each terminal.
* When the exhibitor scans a QR code, the browser will load the `/123456789`. The cookie on the browser identifies
  which exhibitor code to associate the scan with.

### Without cookies:

The embedded browser in iOS (including the QR code scanning app) does not store cookies persistently across sessions,
and it does not inherit persistent cookies from Safari, so this alternate workflow is required:

* The exhibitor scans the QR code, which loads `/123456789`.
* Because the web server does not detect a cookie, it will present the user with a list of codes.
* When the user clicks one of the codes, the browser loads `/123456789/exhibitorcode`, which completes the scan.
* If the user long-presses an exhibitor code, they are given the option to add a custom note to the scan.

## Add a new event

Not supported in the API.

```sql
EXECUTE Scan.New_Event @Event;
```

The stored procedure returns an "EventSecret", which acts like a password to access event data.

## Add a new identity (attendee)

`GET /new/{event code}`

`GET /new/{event code}/{manual integer id}`

Creates a new identity for an existing event. Identities are normally generated randomly,
not in a sequential or otherwise predictable manner, but you can opt to set an ID manually.
This could be useful if you want to integrate with another system and want to inherit the
ID from that data source.

**Note:** When using Eventbrite integration, you should use the Eventbrite Attendee ID as the manual integer ID
to maintain consistency between the scanning system and Eventbrite records.

Return value:
```json
{ "id":"19380729426",
  "url":"https://www.example.com/19380729426",
  "imgsrc":"https://www.example.com/eventcode/19380729426.png",
  "data":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAJ..."}
```

## Scan a code

`GET /{identity}`

`GET /{identity}/{code}`

`POST /{identity}/{code}` with `note` parameter

Scans the identity. Code is optional, and can be added to re-use the identity
for multiple purposes/exhibitors/etc. Remember that the QR URL only contains
the identity, not the code.

Displays a very brief status to the user to indicate if the scan was successful.

Returns HTTP/200 if successful, 500 if not.

Displays an error message if there's no cached code, prompting the user to set up
the terminal first.

For POST requests, the "note" parameter is saved as a plaintext description in
the "Note" column of the scans table.

## Store a exhibitor code as a cookie

`GET /setup`

If the exhibitor uses a smartphone or other browser to scan the QR codes,
the exhibitor code can be stored in a cookie in the browser. A simple web form
found in /setup guides the user.

When the cookie is set in the browser, all scans made with that browser will
include this code. The cookie expires after 24 hours.

You programmatically set the cookie by using a POST request to /setup, with
the exhibitor code in the "code" parameter.

## Retrieve a list of scans

`GET /report/{secret}`

Returns a JSON report of all identities, whether scanned or not. If the identity was
not scanned, the "Scanned" property is blank.

Example:
```json
[{"ID":"19380729426","Scanned":null,"Code":null},
 {"ID":"17560301726","Scanned":"2021-09-27T18:12:23.509Z","Code":null},
 {"ID":"17560301726","Scanned":"2021-09-27T18:12:26.852Z","Code":null},
 {"ID":"17560301726","Scanned":"2021-09-27T18:12:26.852Z","Code":"Microsoft","Note":"Interested in Azure solutions"},
 {"ID":"17560301726","Scanned":"2021-09-27T18:15:34.198Z","Code":"Exhibitor 1","Note":"Spoke about cloud monitoring."},
 {"ID":"17560301726","Scanned":"2021-09-27T18:17:13.824Z","Code":"Exhibitor 2"},
 {"ID":"17560301726","Scanned":"2021-09-27T18:18:42.966Z","Code":"Lunch ticket"}]
```

## View one random scan

`GET /random/{secret}/{code}`

`GET /random/{secret}`

Returns a single, random scan. If the vendor code is specified, the scan is chosen only
from that vendor's scans.

## Expire

`GET /expire`

Evicts all events, identities and scans that have expired. By default, an event expires
365 days after its creation, but this is configured in the Expires column of the Scan.Events table.


# Workflow Integration

## Example integration with Mailchimp

![Sample Mailchimp integration](https://raw.githubusercontent.com/strdco/scan.datasatsto.se/boss/Documentation/microsoft-flow-example.png)

A sample integration would `GET https://scan.example.com/new/EventCode/EventbriteAttendeeID`

... which returns

```json
{ "id":"19380729426",
  "url":"https://scan.example.com/19380729426",
  "imgsrc":"https://scan.example.com/eventcode/19380729426.png",
  "data":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAJ..."}
```

You can parse the output as JSON with the following schema:
```json
{
    "type": "object",
    "properties": {
        "id": {
            "type": "string"
        },
        "url": {
            "type": "string"
        },
        "imgsrc": {
            "type": "string"
        },
        "data": {
            "type": "string"
        }
    }
}
```

... and then write that information back to Mailchimp.

Method: PATCH

URL:
```
https://us5.api.mailchimp.com/3.0/lists/@{triggerOutputs()?['body/list_id']}/members/@{triggerOutputs()?['body/id']}?skip_merge_validation=true
```
Request body:
```json
{
  "merge_fields": {
    "SCANID": "@{body('Parse_JSON')?['id']}",
    "QR": "@{body('Parse_JSON')?['imgsrc']}"
  }
}
```
Use basic authentication; anything goes in the username field, use your API key as the password.


## Eventbrite Complete Attendee Data Export Workflow

1. **Event Setup**: Create event in scanning system and note EventSecret
2. **QR Code Generation**: Generate QR codes using Eventbrite Attendee IDs as manual IDs
3. **Badge Integration**: Include QR codes on attendee badges
4. **Scanning**: Exhibitors scan attendee QR codes during event
5. **Data Export**: 
   - Run export script for specific sponsors: `Export-Attendee-Scans.ps1 -EventId "123" -ConfigFilePath "config.json" -SponsorCode "Microsoft"`
   - Or export all sponsor data: `Export-Attendee-Scans.ps1 -EventId "123" -ConfigFilePath "config.json"`
6. **Deliverables**: Receive CSV files with complete attendee profiles for each sponsor

## Benefits of Eventbrite Integration

- **Complete Attendee Profiles**: No need for separate attendee data management
- **Real-time Data**: Fresh attendee information directly from Eventbrite
- **Automated Processing**: Batch export for all sponsors with single command
- **Professional Output**: Clean CSV files ready for CRM import or follow-up campaigns
- **Error Resilience**: Individual sponsor processing continues even if one fails
- **Fair Raffle System**: Cryptographically secure random selection for prize drawings
- **Privacy Controls**: Optional email inclusion with explicit consent flags
- **Comprehensive Logging**: Detailed verbose output for troubleshooting and audit trails


# Want to contribute?

Pull request welcome. My [DMs are open](https://twitter.com/dhmacher), or create a new issue in the repo.