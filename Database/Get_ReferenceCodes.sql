CREATE OR ALTER PROCEDURE [Scan].[Get_ReferenceCodes]
    @EventSecret UNIQUEIDENTIFIER
AS
BEGIN
    SELECT DISTINCT ReferenceCode 
    FROM Scan.ReferenceCodes
    WHERE EventID = (SELECT EventID FROM Scan.Events WHERE EventSecret = @EventSecret)
    AND ReferenceCode IS NOT NULL
    ORDER BY ReferenceCode
END