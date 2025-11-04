USE [RetailDB]
GO
-- ==========================================
-- Author:		Leon Magara - Portfolio Demo
-- Description:	User security role management (RBAC)
-- Demonstrates:	Security management, audit trails, RBAC
-- ==========================================

-- Add Admin Role
CREATE OR ALTER PROCEDURE [dbo].[AddUserToAdminRole]
	@UserEmail varchar(255),
	@AssignedBy varchar(100)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @UserID int, @AdminRoleID int;
	
	SELECT @UserID = UserID FROM dbo.[User] WHERE Email = @UserEmail;
	IF @UserID IS NULL BEGIN RAISERROR('User not found', 16, 1); RETURN; END
	
	SELECT @AdminRoleID = RoleID FROM dbo.SecurityRole WHERE RoleName = 'Administrator';
	
	DELETE FROM dbo.UserRoleAssignment WHERE UserID = @UserID;
	INSERT INTO dbo.UserRoleAssignment (UserID, RoleID, AssignedBy, AssignedDate)
	VALUES (@UserID, @AdminRoleID, @AssignedBy, GETDATE());
	
	INSERT INTO dbo.SecurityAuditLog (EventType, UserID, Description, PerformedBy, EventDate)
	VALUES ('Role Assignment', @UserID, 'Admin role assigned', @AssignedBy, GETDATE());
END
GO

-- Remove Admin Role
CREATE OR ALTER PROCEDURE [dbo].[RemoveUserFromAdminRole]
	@UserEmail varchar(255),
	@RemovedBy varchar(100)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @UserID int, @AdminRoleID int;
	
	SELECT @UserID = UserID FROM dbo.[User] WHERE Email = @UserEmail;
	IF @UserID IS NULL BEGIN RAISERROR('User not found', 16, 1); RETURN; END
	
	SELECT @AdminRoleID = RoleID FROM dbo.SecurityRole WHERE RoleName = 'Administrator';
	DELETE FROM dbo.UserRoleAssignment WHERE UserID = @UserID AND RoleID = @AdminRoleID;
	
	INSERT INTO dbo.SecurityAuditLog (EventType, UserID, Description, PerformedBy, EventDate)
	VALUES ('Role Removal', @UserID, 'Admin role removed', @RemovedBy, GETDATE());
END
GO
