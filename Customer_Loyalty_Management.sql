USE [RetailDB]
GO
-- ==========================================
-- Author:		Leon Magara - Portfolio Demo  
-- Description:	Loyalty points and tier management system
-- Demonstrates:	Complex business logic, calculations, state management
-- ==========================================

CREATE OR ALTER PROCEDURE [dbo].[ProcessCustomerLoyalty]
	@CustomerID int,
	@ProcessDate date = NULL,
	@Success bit OUTPUT,
	@NewTierLevel varchar(20) OUTPUT,
	@PointsEarned int OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	
	IF @ProcessDate IS NULL SET @ProcessDate = CAST(GETDATE() AS date);
	SET @Success = 0;
	SET @PointsEarned = 0;
	
	BEGIN TRY
	BEGIN TRAN;
	
	-- Get current status
	DECLARE @CurrentPoints int, @CurrentTier varchar(20), @LifetimePoints int, @LastOrderDate date;
	SELECT @CurrentPoints = CurrentPoints, @CurrentTier = TierLevel, @LifetimePoints = LifetimePoints, 
		@LastOrderDate = LastActivityDate
	FROM dbo.CustomerLoyalty WHERE CustomerID = @CustomerID;
	
	-- Enroll if needed
	IF @CurrentPoints IS NULL
	BEGIN
		INSERT INTO dbo.CustomerLoyalty (CustomerID, TierLevel, CurrentPoints, LifetimePoints, EnrollmentDate, LastActivityDate)
		VALUES (@CustomerID, 'Bronze', 0, 0, @ProcessDate, @ProcessDate);
		SET @CurrentPoints = 0; SET @CurrentTier = 'Bronze'; SET @LifetimePoints = 0;
	END
	
	-- Calculate points from new orders
	DECLARE @NewOrders TABLE (OrderID int, OrderTotal decimal(19,2), BasePoints int, BonusPoints int, TotalPoints int);
	
	INSERT INTO @NewOrders (OrderID, OrderTotal, BasePoints, BonusPoints)
	SELECT oh.OrderID, oh.OrderTotal, CAST(oh.OrderTotal AS int),
		CASE WHEN oh.OrderTotal >= 500 THEN 500 WHEN oh.OrderTotal >= 250 THEN 250 WHEN oh.OrderTotal >= 100 THEN 100 ELSE 0 END
	FROM dbo.OrderHeader oh
	WHERE oh.CustomerID = @CustomerID AND CAST(oh.OrderDate AS date) > ISNULL(@LastOrderDate, '1900-01-01')
		AND CAST(oh.OrderDate AS date) <= @ProcessDate AND oh.OrderStatus = 'Completed';
	
	-- Apply tier multiplier
	UPDATE @NewOrders SET TotalPoints = (BasePoints + BonusPoints) * 
		CASE @CurrentTier WHEN 'Platinum' THEN 2.0 WHEN 'Gold' THEN 1.5 WHEN 'Silver' THEN 1.25 ELSE 1.0 END;
	
	SELECT @PointsEarned = ISNULL(SUM(TotalPoints), 0) FROM @NewOrders;
	
	-- Calculate YTD metrics
	DECLARE @YTDSpend decimal(19,2), @TotalOrders int;
	SELECT @YTDSpend = ISNULL(SUM(OrderTotal), 0), @TotalOrders = COUNT(*)
	FROM dbo.OrderHeader
	WHERE CustomerID = @CustomerID AND OrderDate >= DATEFROMPARTS(YEAR(@ProcessDate), 1, 1)
		AND OrderDate <= @ProcessDate AND OrderStatus = 'Completed';
	
	-- Determine new tier
	IF @LifetimePoints + @PointsEarned >= 50000 OR (@YTDSpend >= 10000 AND @TotalOrders >= 50)
		SET @NewTierLevel = 'Platinum';
	ELSE IF @LifetimePoints + @PointsEarned >= 25000 OR (@YTDSpend >= 5000 AND @TotalOrders >= 25)
		SET @NewTierLevel = 'Gold';
	ELSE IF @LifetimePoints + @PointsEarned >= 10000 OR (@YTDSpend >= 2500 AND @TotalOrders >= 10)
		SET @NewTierLevel = 'Silver';
	ELSE
		SET @NewTierLevel = 'Bronze';
	
	-- Update loyalty record
	UPDATE dbo.CustomerLoyalty
	SET CurrentPoints = CurrentPoints + @PointsEarned, LifetimePoints = LifetimePoints + @PointsEarned,
		TierLevel = @NewTierLevel, LastActivityDate = @ProcessDate, LastModifiedDate = GETDATE()
	WHERE CustomerID = @CustomerID;
	
	-- Log tier change if occurred
	IF @CurrentTier <> @NewTierLevel
	BEGIN
		INSERT INTO dbo.CustomerLoyaltyHistory (CustomerID, ChangeDate, ChangeType, OldValue, NewValue, ProcessedBy)
		VALUES (@CustomerID, @ProcessDate, 'Tier Change', @CurrentTier, @NewTierLevel, SYSTEM_USER);
	END
	
	-- Log points activity
	IF @PointsEarned > 0
	BEGIN
		INSERT INTO dbo.LoyaltyPointsTransaction (CustomerID, TransactionDate, TransactionType, PointsChange, Description)
		SELECT @CustomerID, @ProcessDate, 'Purchase', TotalPoints, 'Order #' + CAST(OrderID AS varchar(20))
		FROM @NewOrders WHERE TotalPoints > 0;
	END
	
	SET @Success = 1;
	COMMIT TRAN;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END
GO
