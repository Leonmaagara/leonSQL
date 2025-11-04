USE [RetailDB]
GO
-- ==========================================
-- Author:		Leon Magara - Portfolio Demo
-- Description:	Import high-value products from external supplier system
-- Demonstrates:	ETL, transactions, cursors, multi-table sync, error handling
-- ==========================================

CREATE OR ALTER PROCEDURE [dbo].[ImportHighValueProducts]
	@SupplierID int,
	@CurrentUser varchar(100),
	@ImportType varchar(25),
	@EffectiveDate datetime,
	@Success bit OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Success = 0;

	-- Get supplier's external database ID
	DECLARE @ExternalSupplierID varchar(50) = (
		SELECT ExternalSystemID FROM dbo.SupplierLink WHERE SupplierID = @SupplierID
	);

	-- Temp table for incoming products
	DECLARE @IncomingProducts TABLE (
		ProductSKU varchar(50), ProductName varchar(250), UnitCost decimal(19,4),
		RetailPrice decimal(19,4), CategoryCode varchar(20), UnitOfMeasure varchar(10),
		MinOrderQuantity int, LeadTimeDays int, Description nvarchar(max)
	);

	-- Extract from external system (high-value items only)
	INSERT INTO @IncomingProducts
	SELECT SKU, ProductName, WholesalePrice, SuggestedRetailPrice, CategoryCode,
		UOM, MinimumOrder, LeadTime, LongDescription
	FROM SupplierDB.dbo.Products
	WHERE SupplierID = @ExternalSupplierID 
		AND SuggestedRetailPrice > 500  -- High-value filter
		AND ActiveFlag = 1;

	BEGIN TRY
	BEGIN TRAN;

	DECLARE @WarehouseID int = (SELECT DefaultWarehouseID FROM dbo.Supplier WHERE SupplierID = @SupplierID);

	-- Store existing products
	DECLARE @ExistingProducts TABLE (ProductID int);
	INSERT INTO @ExistingProducts
	SELECT ProductID FROM dbo.Product WHERE SupplierID = @SupplierID;

	-- Delete existing if full import
	IF @ImportType = 'Full'
	BEGIN
		DELETE pa FROM dbo.ProductAttribute pa INNER JOIN @ExistingProducts ep ON pa.ProductID = ep.ProductID;
		DELETE ph FROM dbo.PricingHistory ph INNER JOIN @ExistingProducts ep ON ph.ProductID = ep.ProductID;
		DELETE inv FROM dbo.Inventory inv INNER JOIN @ExistingProducts ep ON inv.ProductID = ep.ProductID;
		DELETE p FROM dbo.Product p INNER JOIN @ExistingProducts ep ON p.ProductID = ep.ProductID;
	END

	-- Process each product with cursor
	DECLARE @Cursor AS CURSOR, @InsertedProductID int, @CategoryID int;
	DECLARE @ProductSKU varchar(50), @ProductName varchar(250), @UnitCost decimal(19,4);
	DECLARE @RetailPrice decimal(19,4), @CategoryCode varchar(20), @UnitOfMeasure varchar(10);
	DECLARE @MinOrderQty int, @LeadTime int, @Description nvarchar(max);
	DECLARE @MarginPercent decimal(5,2), @MarkupPercent decimal(5,2);

	SET @Cursor = CURSOR FOR
	SELECT ProductSKU, ProductName, UnitCost, RetailPrice, CategoryCode,
		UnitOfMeasure, MinOrderQuantity, LeadTimeDays, Description
	FROM @IncomingProducts ORDER BY ProductSKU;
	
	OPEN @Cursor;
	FETCH NEXT FROM @Cursor INTO @ProductSKU, @ProductName, @UnitCost, @RetailPrice, 
		@CategoryCode, @UnitOfMeasure, @MinOrderQty, @LeadTime, @Description;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		-- Get or create category
		IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategory WHERE CategoryCode = @CategoryCode)
			INSERT INTO dbo.ProductCategory (CategoryCode, CategoryName, Active) VALUES (@CategoryCode, @CategoryCode, 1);
		SET @CategoryID = (SELECT CategoryID FROM dbo.ProductCategory WHERE CategoryCode = @CategoryCode);

		-- Calculate margins
		SET @MarginPercent = CASE WHEN @RetailPrice > 0 THEN ((@RetailPrice - @UnitCost) / @RetailPrice) * 100 ELSE 0 END;
		SET @MarkupPercent = CASE WHEN @UnitCost > 0 THEN ((@RetailPrice - @UnitCost) / @UnitCost) * 100 ELSE 0 END;

		-- Insert product
		INSERT INTO dbo.Product (SupplierID, SKU, ProductName, CategoryID, UnitOfMeasure, MinOrderQuantity, LeadTimeDays, ActiveFlag, CreatedBy, CreatedDate)
		VALUES (@SupplierID, @ProductSKU, @ProductName, @CategoryID, @UnitOfMeasure, @MinOrderQty, @LeadTime, 1, @CurrentUser, GETDATE());
		SET @InsertedProductID = SCOPE_IDENTITY();

		-- Insert pricing
		INSERT INTO dbo.PricingHistory (ProductID, UnitCost, RetailPrice, MarginPercent, MarkupPercent, EffectiveDate, CreatedBy)
		VALUES (@InsertedProductID, @UnitCost, @RetailPrice, @MarginPercent, @MarkupPercent, @EffectiveDate, @CurrentUser);

		-- Insert description
		IF @Description IS NOT NULL
			INSERT INTO dbo.ProductAttribute (ProductID, AttributeType, AttributeValue, CreatedBy, CreatedDate)
			VALUES (@InsertedProductID, 'Description', @Description, @CurrentUser, GETDATE());

		-- Initialize inventory
		INSERT INTO dbo.Inventory (ProductID, WarehouseID, QuantityOnHand, QuantityReserved, ReorderPoint, LastUpdated)
		VALUES (@InsertedProductID, @WarehouseID, 0, 0, @MinOrderQty * 2, GETDATE());

		FETCH NEXT FROM @Cursor INTO @ProductSKU, @ProductName, @UnitCost, @RetailPrice, 
			@CategoryCode, @UnitOfMeasure, @MinOrderQty, @LeadTime, @Description;
	END
	
	CLOSE @Cursor;
	DEALLOCATE @Cursor;

	SET @Success = 1;
	COMMIT TRAN;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
	
	RETURN;
END
GO
