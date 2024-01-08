CREATE TABLE dbo.Customer (
    customer_id INT IDENTITY(1, 1) NOT NULL,
    firstname VARCHAR(25) NOT NULL,
    lastname VARCHAR(25) NOT NULL,
    email VARCHAR(25) NULL,
    created_date DATETIME NOT NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[Customer]
ADD CONSTRAINT [DF_Customer_CreateDate] DEFAULT (getdate()) FOR [created_date]
GO
