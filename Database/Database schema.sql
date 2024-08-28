CREATE SCHEMA Scan;
GO
-- Events
---------
CREATE TABLE Scan.Events (
    EventID     int IDENTITY(1, 1) NOT NULL,
    [Event]     varchar(50) NOT NULL,
    EventSecret uniqueidentifier DEFAULT (NEWID()) NOT NULL,
    Expires     date DEFAULT (DATEADD(day, 365, SYSUTCDATETIME())) NOT NULL,
    CONSTRAINT PK_Scan_Events PRIMARY KEY CLUSTERED (EventID),
    CONSTRAINT UQ_Scan_Events UNIQUE ([Event])
);
GO
-- Identities
-------------
CREATE TABLE Scan.Identities (
    EventID     int NOT NULL,
    ID          bigint NOT NULL,
    Created     datetime2(3) NOT NULL,
    CONSTRAINT PK_Scan_Identities PRIMARY KEY CLUSTERED (ID),
    CONSTRAINT FK_Scan_Identities_Events FOREIGN KEY (EventID) REFERENCES Scan.Events (EventID)
);
GO
-- Exhibitor codes
CREATE TABLE Scan.ReferenceCodes (
    EventID     int NOT NULL,
    ReferenceCode varchar(20) NOT NULL,
    CONSTRAINT PK_Scan_ReferenceCodes PRIMARY KEY CLUSTERED (EventID, ReferenceCode),
    CONSTRAINT FK_Scan_ReferenceCodes_Events FOREIGN KEY (EventID) REFERENCES Scan.Events (EventID)
);
-- Scans
--------
CREATE TABLE Scan.Scans (
    ID          bigint NOT NULL,
    Scanned     datetime2(3) NOT NULL,
    ReferenceCode varchar(20) NULL,
    Note        nvarchar(max) NULL,
    CONSTRAINT PK_Scan_Scans PRIMARY KEY CLUSTERED (Id, Scanned),
    CONSTRAINT FK_Scan_Scans_Identities FOREIGN KEY (ID) REFERENCES Scan.Identities (ID)
);
GO

-------------------------------------------------------------------------------
--- Create a new event
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE Scan.New_Event
    @Event      varchar(50)
AS

SET NOCOUNT ON;

INSERT INTO Scan.Events ([Event])
OUTPUT inserted.EventSecret
VALUES (@Event);

GO

-------------------------------------------------------------------------------
--- Create a new identity
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE Scan.New_Identity
    @Event      varchar(50),
    @ID         bigint=NULL
AS

SET NOCOUNT ON;

DECLARE @Done       bit=0,
        @Attempts   tinyint=0,
        @EventID    int=(SELECT EventID FROM Scan.Events WHERE [Event]=@Event);

--- If the event does not exist, fail.
IF (@EventID IS NULL) BEGIN;
    THROW 50001, 'Invalid event code', 1;
    RETURN;
END;

--- If the request specified an ID, use that:
IF (@ID IS NOT NULL)
    INSERT INTO Scan.Identities (ID, EventID, Created)
    VALUES (@ID, @EventID, SYSUTCDATETIME());

IF (@ID IS NULL) BEGIN;
    --- Try up to a hundred times to allocate a new, random identity:
    WHILE (@Done=0 AND @Attempts<100) BEGIN;
        BEGIN TRY;
            SET @ID=10000000000.+10000000000.*RAND(CHECKSUM(NEWID()));
            SET @Attempts=@Attempts+1;

            INSERT INTO Scan.Identities (ID, EventID, Created)
            VALUES (@ID, @EventID, SYSUTCDATETIME());

            SET @Done=1;
        END TRY
        BEGIN CATCH;
            SET @ID=NULL; 
            SET @Done=0;
        END CATCH;
    END;
END;

--- If we could allocate an identity, return it:
IF (@ID IS NOT NULL)
    SELECT @ID AS ID;

--- If we couldn't allocate an identity, fail:
IF (@ID IS NULL)
    THROW 50001, 'You''re not going to believe this. But I think we ran out of identity numbers', 1;

GO

-------------------------------------------------------------------------------
--- Scan an identity
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE Scan.New_Scan
    @ID             bigint,
    @ReferenceCode  varchar(20)=NULL,
    @Note           nvarchar(max)=NULL
AS

SET NOCOUNT ON;

IF ((SELECT Expires
     FROM Scan.Events
     WHERE EventID=(SELECT EventID
                    FROM Scan.Identities
                    WHERE ID=@ID)
    )<=CAST(SYSDATETIME() AS date)) BEGIN;

    SELECT -1 AS [ID];
    THROW 50001, 'This event is no longer active', 1;
    RETURN;
END;

--- Create the reference code if
--- * the identity exists, and
--- * the reference code doesn't already exist:
INSERT INTO Scan.ReferenceCodes (EventID, ReferenceCode)
SELECT EventID, @ReferenceCode
FROM Scan.Identities
WHERE ID=@ID
EXCEPT
SELECT EventID, ReferenceCode
FROM Scan.ReferenceCodes;

BEGIN TRY;
    --- Add the user scan if the identity exists:
    INSERT INTO Scan.Scans (ID, Scanned, ReferenceCode, Note)
    OUTPUT inserted.ID
    SELECT @ID, SYSUTCDATETIME(), @ReferenceCode, @Note
    FROM Scan.Identities
    WHERE ID=@ID;
END TRY
BEGIN CATCH;
    SELECT -1 AS [ID];
END CATCH;

GO

-------------------------------------------------------------------------------
--- Get a list of exhibitor codes for an identity. Used by /setup?id=...
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE Scan.Get_Codes
    @ID             bigint
AS

SELECT c.ReferenceCode
FROM Scan.Identities AS i
INNER JOIN Scan.ReferenceCodes AS c ON i.EventID=c.EventID
WHERE i.ID=@ID
ORDER BY c.ReferenceCode;

GO

-------------------------------------------------------------------------------
--- Fetch all scans for an event
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE Scan.Get_Scans
    @EventSecret        uniqueidentifier
AS

SELECT i.ID, s.Scanned, s.ReferenceCode AS Code, s.Note
FROM Scan.Events AS e
INNER JOIN Scan.Identities AS i ON e.EventID=i.EventID
LEFT JOIN Scan.Scans AS s ON i.ID=s.ID
WHERE e.EventSecret=@EventSecret
ORDER BY s.Scanned;

GO

-------------------------------------------------------------------------------
--- Fetch a random scans for an event
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE Scan.Get_Random
    @EventSecret        uniqueidentifier,
    @ReferenceCode      varchar(20)
AS

SELECT TOP (1) ID, Scanned, Code
FROM (
    SELECT DISTINCT i.ID, s.Scanned, s.ReferenceCode AS Code
    FROM Scan.Events AS e
    INNER JOIN Scan.Identities AS i ON e.EventID=i.EventID
    INNER JOIN Scan.Scans AS s ON i.ID=s.ID
    WHERE e.EventSecret=@EventSecret
    AND (s.ReferenceCode=@ReferenceCode OR NULLIF(@ReferenceCode, '') IS NULL)
) AS sub
ORDER BY NEWID();

GO

-------------------------------------------------------------------------------
--- Evict old identities and scans
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE Scan.Expire
AS

DECLARE @today date=SYSUTCDATETIME();

BEGIN TRANSACTION;

    --- Events -> Identities -> Scans:
    DELETE s
    FROM Scan.Events AS e
    INNER JOIN Scan.Identities AS i ON e.EventID=i.EventID
    INNER JOIN Scan.Scans AS s ON i.ID=s.ID
    WHERE e.Expires<@today;

    --- Events -> Identities
    DELETE i
    FROM Scan.Events AS e
    INNER JOIN Scan.Identities AS i ON e.EventID=i.EventID
    WHERE e.Expires<@today;

    --- Events -> ReferenceCodes
    DELETE c
    FROM Scan.Events AS e
    INNER JOIN Scan.ReferenceCodes AS c ON e.EventID=c.EventID
    WHERE e.Expires<@today;

    --- Events
    DELETE e
    OUTPUT deleted.Event AS ExpiredEvent
    FROM Scan.Events AS e
    WHERE e.Expires<@today;

COMMIT TRANSACTION;

GO