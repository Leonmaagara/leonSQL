USE [AnalyticsDB]
GO
-- ==========================================
-- Author:		Leon Magara - Portfolio Demo
-- Description:	Multi-schema data warehouse for e-commerce analytics
-- Demonstrates:	Schema design, staging patterns, metadata, constraints
-- ==========================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
BEGIN TRAN;

-- Create schemas
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Staging') EXEC('CREATE SCHEMA [Staging]');
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Transform') EXEC('CREATE SCHEMA [Transform]');
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Validation') EXEC('CREATE SCHEMA [Validation]');
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Analytics') EXEC('CREATE SCHEMA [Analytics]');
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Reference') EXEC('CREATE SCHEMA [Reference]');

-- Reference tables
DROP TABLE IF EXISTS [Reference].[MetricCalculationRules];
CREATE TABLE [Reference].[MetricCalculationRules] (
	RuleID int PRIMARY KEY IDENTITY(1,1),
	MetricName varchar(100) UNIQUE NOT NULL,
	CalculationFormula varchar(500) NOT NULL,
	SourceTable varchar(100) NOT NULL,
	RefreshFrequency varchar(20) NOT NULL,
	Active bit DEFAULT 1,
	EffectiveDate date NOT NULL,
	CreatedBy varchar(100) NOT NULL,
	CreatedDate datetime DEFAULT GETDATE(),
	CONSTRAINT CK_RefreshFrequency CHECK (RefreshFrequency IN ('Hourly','Daily','Weekly','Monthly'))
);

-- Staging tables  
DROP TABLE IF EXISTS [Staging].[Customer];
CREATE TABLE [Staging].[Customer] (
	StagingID int PRIMARY KEY IDENTITY(1,1),
	CustomerID varchar(50), FirstName varchar(100), LastName varchar(100),
	Email varchar(255), PhoneNumber varchar(20), CustomerSegment varchar(50),
	AccountCreatedDate datetime, LastPurchaseDate datetime,
	LifetimeValue decimal(19,2), CustomerStatus varchar(20),
	SourceSystem varchar(50) NOT NULL, LoadDate datetime DEFAULT GETDATE(),
	IsValidRecord bit, ValidationErrors varchar(max)
);

DROP TABLE IF EXISTS [Staging].[OrderHeader];
CREATE TABLE [Staging].[OrderHeader] (
	StagingID int PRIMARY KEY IDENTITY(1,1),
	OrderID varchar(50), CustomerID varchar(50), OrderDate datetime,
	ShipDate datetime, OrderTotal decimal(19,2), TaxAmount decimal(19,2),
	ShippingAmount decimal(19,2), DiscountAmount decimal(19,2),
	PaymentMethod varchar(50), OrderStatus varchar(20),
	SourceSystem varchar(50) NOT NULL, LoadDate datetime DEFAULT GETDATE(),
	IsValidRecord bit, ValidationErrors varchar(max)
);

-- Validation tables
DROP TABLE IF EXISTS [Validation].[DataQualityRules];
CREATE TABLE [Validation].[DataQualityRules] (
	RuleID int PRIMARY KEY IDENTITY(1,1),
	TableName varchar(100) NOT NULL, ColumnName varchar(100) NOT NULL,
	RuleType varchar(50) NOT NULL, RuleDefinition varchar(max) NOT NULL,
	Severity varchar(20) NOT NULL, Active bit DEFAULT 1,
	CreatedBy varchar(100) NOT NULL, CreatedDate datetime DEFAULT GETDATE(),
	CONSTRAINT CK_Severity CHECK (Severity IN ('Critical','Warning','Info'))
);

-- Analytics tables
DROP TABLE IF EXISTS [Analytics].[DimCustomer];
CREATE TABLE [Analytics].[DimCustomer] (
	CustomerKey int PRIMARY KEY IDENTITY(1,1),
	CustomerID varchar(50) NOT NULL, FullName varchar(200) NOT NULL,
	Email varchar(255) NOT NULL, CustomerSegment varchar(50) NOT NULL,
	FirstPurchaseDate date NOT NULL, LastPurchaseDate date,
	LifetimeValue decimal(19,2) DEFAULT 0,
	EffectiveDate date NOT NULL, ExpirationDate date, IsCurrent bit DEFAULT 1,
	SourceSystem varchar(50) NOT NULL, CreatedDate datetime DEFAULT GETDATE()
);

DROP TABLE IF EXISTS [Analytics].[FactSales];
CREATE TABLE [Analytics].[FactSales] (
	SalesKey bigint PRIMARY KEY IDENTITY(1,1),
	DateKey int NOT NULL, CustomerKey int NOT NULL, ProductKey int NOT NULL,
	OrderQuantity int NOT NULL, UnitPrice decimal(19,4) NOT NULL,
	ExtendedAmount decimal(19,2) NOT NULL, DiscountAmount decimal(19,2) DEFAULT 0,
	TaxAmount decimal(19,2) DEFAULT 0, TotalAmount decimal(19,2) NOT NULL,
	ProfitAmount decimal(19,2), ProfitMargin decimal(5,2),
	LoadDate datetime DEFAULT GETDATE()
);

-- Extended properties
EXEC sp_addextendedproperty @name = N'Description',
	@value = N'Staging area for customer data validation before loading',
	@level0type = N'SCHEMA', @level0name = 'Staging',
	@level1type = N'TABLE', @level1name = 'Customer';

-- Insert sample rules
INSERT INTO [Reference].[MetricCalculationRules] 
	(MetricName, CalculationFormula, SourceTable, RefreshFrequency, EffectiveDate, CreatedBy)
VALUES
	('Daily Revenue', 'SUM(TotalAmount)', 'Analytics.FactSales', 'Daily', '2024-01-01', 'System'),
	('Avg Order Value', 'AVG(TotalAmount)', 'Analytics.FactSales', 'Daily', '2024-01-01', 'System');

INSERT INTO [Validation].[DataQualityRules] (TableName, ColumnName, RuleType, RuleDefinition, Severity, Active, CreatedBy)
VALUES
	('Staging.Customer', 'Email', 'Format', 'Must contain @ symbol', 'Critical', 1, 'System'),
	('Staging.OrderHeader', 'OrderTotal', 'Range', 'Must be >= 0', 'Critical', 1, 'System');

COMMIT TRAN;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
	THROW;
END CATCH;
GO
