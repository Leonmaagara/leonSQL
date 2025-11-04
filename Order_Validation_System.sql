USE [RetailDB]
GO
-- ==========================================
-- Author:		Leon Magara - Portfolio Demo
-- Description:	Multi-criteria order validation and compliance
-- Demonstrates:	Validation framework, business rules, error handling
-- ==========================================

CREATE OR ALTER PROCEDURE [dbo].[ValidateOrderCompliance]
	@OrderID int,
	@ValidationLevel varchar(20) = 'Standard',
	@IsValid bit OUTPUT,
	@ValidationErrors varchar(max) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @IsValid = 1;
	SET @ValidationErrors = '';
	
	DECLARE @Errors TABLE (ErrorCode varchar(20), ErrorMessage varchar(500), Severity varchar(20));
	
	BEGIN TRY
	BEGIN TRAN;
	
	-- Get order details
	DECLARE @CustomerID int, @OrderDate datetime, @OrderTotal decimal(19,2), @ShippingCountry varchar(100);
	SELECT @CustomerID = CustomerID, @OrderDate = OrderDate, @OrderTotal = OrderTotal, @ShippingCountry = ShippingCountry
	FROM dbo.OrderHeader WHERE OrderID = @OrderID;
	
	-- Validation 1: Order completeness
	IF @CustomerID IS NULL INSERT INTO @Errors VALUES ('ORD001', 'Missing customer', 'Critical');
	IF @OrderDate IS NULL INSERT INTO @Errors VALUES ('ORD002', 'Missing order date', 'Critical');
	IF @OrderTotal IS NULL OR @OrderTotal < 0 INSERT INTO @Errors VALUES ('ORD003', 'Invalid total', 'Critical');
	
	-- Validation 2: Credit limit
	DECLARE @CreditLimit decimal(19,2), @CurrentBalance decimal(19,2), @AvailableCredit decimal(19,2);
	SELECT @CreditLimit = CreditLimit, @CurrentBalance = CurrentBalance FROM dbo.Customer WHERE CustomerID = @CustomerID;
	SET @AvailableCredit = @CreditLimit - @CurrentBalance;
	
	IF @OrderTotal > @AvailableCredit
		INSERT INTO @Errors VALUES ('CRED001', 'Exceeds credit limit', 'Critical');
	
	-- Validation 3: Inventory check
	IF EXISTS (
		SELECT 1 FROM dbo.OrderDetail od
		INNER JOIN dbo.Inventory i ON od.ProductID = i.ProductID
		WHERE od.OrderID = @OrderID AND od.OrderQuantity > (i.QuantityOnHand - i.QuantityReserved)
	)
		INSERT INTO @Errors VALUES ('INV001', 'Insufficient inventory', 'Critical');
	
	-- Validation 4: Restricted countries
	IF EXISTS (SELECT 1 FROM dbo.RestrictedCountries WHERE CountryName = @ShippingCountry AND Active = 1)
		INSERT INTO @Errors VALUES ('COMP001', 'Restricted shipping destination', 'Critical');
	
	-- Validation 5: Order total consistency
	DECLARE @CalculatedTotal decimal(19,2);
	SELECT @CalculatedTotal = SUM((OrderQuantity * UnitPrice) - ISNULL(DiscountAmount, 0))
	FROM dbo.OrderDetail WHERE OrderID = @OrderID;
	
	IF ABS(@OrderTotal - @CalculatedTotal) > 0.01
		INSERT INTO @Errors VALUES ('ORD005', 'Total mismatch', 'Critical');
	
	-- Determine validity
	IF EXISTS (SELECT 1 FROM @Errors WHERE Severity = 'Critical') SET @IsValid = 0;
	IF @ValidationLevel = 'Strict' AND EXISTS (SELECT 1 FROM @Errors WHERE Severity = 'Warning') SET @IsValid = 0;
	
	-- Build error message
	SELECT @ValidationErrors = @ValidationErrors + '[' + Severity + '] ' + ErrorCode + ': ' + ErrorMessage + '; '
	FROM @Errors ORDER BY CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END, ErrorCode;
	
	-- Log validation
	INSERT INTO dbo.OrderValidationLog (OrderID, ValidationDate, ValidationLevel, IsValid, ValidationErrors, ValidatedBy)
	VALUES (@OrderID, GETDATE(), @ValidationLevel, @IsValid, @ValidationErrors, SYSTEM_USER);
	
	COMMIT TRAN;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		SET @IsValid = 0;
		SET @ValidationErrors = 'Validation error: ' + ERROR_MESSAGE();
		THROW;
	END CATCH;
END
GO
