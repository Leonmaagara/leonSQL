USE [RetailDB]
GO
-- ==========================================
-- Author:		Leon Magara - Portfolio Demo
-- Description:	Product pricing and cost rate management
-- Demonstrates:	Reference data, temporal data, audit trails
-- ==========================================

-- Update Base Cost Rates
CREATE OR ALTER PROCEDURE [dbo].[UpdateBaseCostRates]
	@EffectiveDate date,
	@CostInflationPercent decimal(5,2),
	@UpdatedBy varchar(100)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	
	BEGIN TRY
	BEGIN TRAN;
	
	-- Expire current rates
	UPDATE dbo.BaseCostRates
	SET ExpirationDate = DATEADD(day, -1, @EffectiveDate),
		ModifiedBy = @UpdatedBy,
		ModifiedDate = GETDATE()
	WHERE ExpirationDate IS NULL OR ExpirationDate > @EffectiveDate;
	
	-- Insert new rates with inflation adjustment
	INSERT INTO dbo.BaseCostRates (CategoryID, BaseRate, EffectiveDate, CreatedBy, CreatedDate)
	SELECT CategoryID, 
		BaseRate * (1 + (@CostInflationPercent / 100)),
		@EffectiveDate,
		@UpdatedBy,
		GETDATE()
	FROM dbo.BaseCostRates
	WHERE ExpirationDate = DATEADD(day, -1, @EffectiveDate);
	
	-- Log the update
	INSERT INTO dbo.RateChangeLog (ChangeDate, RateType, InflationPercent, ChangedBy)
	VALUES (@EffectiveDate, 'Base Cost', @CostInflationPercent, @UpdatedBy);
	
	COMMIT TRAN;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END
GO

-- Update Markup Rates
CREATE OR ALTER PROCEDURE [dbo].[UpdateMarkupRates]
	@CategoryID int = NULL,
	@NewMarkupPercent decimal(5,2),
	@EffectiveDate date,
	@UpdatedBy varchar(100)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	
	BEGIN TRY
	BEGIN TRAN;
	
	-- Update specific category or all if NULL
	IF @CategoryID IS NOT NULL
	BEGIN
		UPDATE dbo.CategoryMarkupRates
		SET MarkupPercent = @NewMarkupPercent,
			EffectiveDate = @EffectiveDate,
			ModifiedBy = @UpdatedBy,
			ModifiedDate = GETDATE()
		WHERE CategoryID = @CategoryID;
	END
	ELSE
	BEGIN
		UPDATE dbo.CategoryMarkupRates
		SET MarkupPercent = @NewMarkupPercent,
			EffectiveDate = @EffectiveDate,
			ModifiedBy = @UpdatedBy,
			ModifiedDate = GETDATE();
	END
	
	-- Log the change
	INSERT INTO dbo.RateChangeLog (ChangeDate, RateType, CategoryID, NewRate, ChangedBy)
	VALUES (@EffectiveDate, 'Markup', @CategoryID, @NewMarkupPercent, @UpdatedBy);
	
	COMMIT TRAN;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END
GO
