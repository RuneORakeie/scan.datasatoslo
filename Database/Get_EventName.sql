CREATE OR ALTER PROCEDURE [Scan].[Get_EventName]
    @EventSecret UNIQUEIDENTIFIER
AS
BEGIN
    SELECT [Event] as EventName
    FROM Scan.Events 
    WHERE EventSecret = @EventSecret
END