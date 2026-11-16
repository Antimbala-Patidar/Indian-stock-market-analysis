
---Step 1 : Import your pyhton data into sql server and checks data

CREATE DATABASE StockMarketAnalytics;
GO

USE StockMarketAnalytics;
GO

--Select the top 10 rows from stock_analysis_results
 SELECT TOP  10 *
 FROM [dbo].[stock_analysis_results];

 --Count the total no of rows
 SELECT COUNT(*) AS TotalRows
 FROM [dbo].[stock_analysis_results];

 --Count how many companies you have:
 SELECT company,
 count(*) AS total_records
 FROM [dbo].[stock_analysis_results]
 GROUP BY company;

 
--- step 2 : Create a Dimension Table and Fact Table here

--- Create a DimCompany table
CREATE TABLE dbo.DimCompany
(
  CompanyKey INT IDENTITY(1,1) ---Here it automatically generte key like 1,2,3,4,5
  PRIMARY KEY,
  CompanyName VARCHAR(100),
  Symbol VARCHAR(50),
  Sector  VARCHAR(50)
  );

(
  --- Insert the distinct companies from your stock_analysis_table
  INSERT INTO dbo.DimCompany
  (
   CompanyName,
   Symbol,
   Sector
   )
   SELECT DISTINCT
       company,
       symbol,
       sector
   FROM [dbo].[stock_analysis_results];

   --- Check the results:
   SELECT *
   FROM dbo.DimCompany;

   --- Create DimDate Table
   CREATE TABLE dbo.DimDate
   (
   Date_Key INT PRIMARY KEY,
   Full_Date DATE,
   Day_Number INT,
   Month_Number INT,
   Month_Name VARCHAR(20),
   Quater_Number INT,
   Year_Number INT
   );

   --- populate the table using distinct dates in your stock data :
   INSERT INTO dbo.DimDate
   (
   Date_Key ,
   Full_Date ,
   Day_Number ,
   Month_Number ,
   Month_Name ,
   Quater_Number ,
   Year_Number 
   )
   SELECT DISTINCT
        YEAR([date]) * 10000
            + MONTH([date]) * 100
            + DAY([date]) AS DateKey,
        [date],
        DAY([date]),
        MONTH([date]),
        DATENAME(MONTH, [date]),
        DATEPART(QUARTER, [date]),
        YEAR([date])
    FROM dbo.stock_analysis_results;

-- Check the table:
SELECT *
FROM dbo.DimDate
ORDER BY Full_Date;

-- Create Your fact table
CREATE TABLE dbo.FactStockPrices
(
 Date_Key INT,
 Company_Key INT,
 Open_Price DECIMAL(18,2),
 High_Price DECIMAL(18,2),
 Low_Price DECIMAL(18,2),
 Close_Price DECIMAL(18,2),
 volume BIGINT,

 PRIMARY KEY (Date_Key,Company_Key),
 FOREIGN kEY(Date_Key) REFERENCES
 dbo.DimDate(Date_Key),
 FOREIGN KEY (company_Key)
 REFERENCES
 dbo.DimCompany(CompanyKey)
 );

 --- Insert the data

 INSERT INTO dbo.FactStockPrices
 (
   Date_Key,
   Company_Key,
   Open_Price,
   High_Price,
   Low_Price,
   Close_Price,
   volume
   )
   SELECT
   d.Date_Key,
   c.CompanyKey,
   s.[open],
   s.[high],
   s.[low],
   s.[close],
   s.volume
FROM stock_analysis_results AS s
INNER JOIN dbo.DimDate AS d
    ON s.[date] = d.Full_Date
INNER JOIN dbo.DimCompany AS c
    ON s.company = c.CompanyName;

-- Check your fact table:
SELECT TOP 10 *
FROM dbo.FactStockPrices;

-- Count the records:
SELECT COUNT(*) AS total_rows
FROM dbo.FactStockPrices;


--Business Questions : Which company generated the highest price return ??
WITH CompanyPerformance AS
(
    SELECT
        c.CompanyName,
        MIN(d.Full_Date) AS FirstDate,
        MAX(d.Full_Date) AS LastDate
    FROM dbo.FactStockPrices AS f
    INNER JOIN dbo.DimCompany AS c
         ON f.Company_Key = c.Company_Key
         INNER JOIN dbo.DimDate As d
            ON f.Date_Key = d.Date_Key
         GROUP BY c.CompanyName
         ),
FirstPrices AS
(
  SELECT
       C.CompanyName,
       f.ClosePrice AS FirstClose
  FROM dbo.FactStockPrices AS f
  INNER JOIN dbo.DimCompany AS c 
       ON f.CompanyKey = c.CompanyKey
  INNER JOIN dbo.DimDate AS d
  ON f.DateKey = d.DateKey
  INNER JOIN CompanyPerformance AS p
  ON c.CompanyName = p.CompanyName
  AND d.FullDate = p.FirstDate ),
  LastPrices AS
  (
  SELECT c.CompanyName,
  f.ClosePrice As LastClose
  FROM dbo.FactStockPrices AS f
  INNER JOIN dbo.DimCompany AS c
  ON f.CompanyKey = c.CompanyKey
  INNER JOIN CompanyPerformance AS p
  ON c.CompanyName = p.CompanyName
  AND d.FullDate = p.LastDate)
  SELECT 
       firstp.CompanyName,
       firstp.FirstClose,
       lastp.LastClose,
       CAST((lastp.LastClose - firstp.FirstClose)*100.0/NULLIF(firstp.FirstClose,0)
       AS DECIMAL(10,2)
       ) AS PriceRetrunpct
       FROM FirstPrices AS firstp
       INNER JOIN LastPrices AS lastp
       ON firstp.companyName=lastp.companyName
       ORDER BY PriceReturnpct Desc;



---Which company had the highest average daily trading volume???

SELECT
      c.CompanyName,
      AVG(CAST(f.volume AS FLOAT)) AS
AverageDailyVolume
FROM dbo.FactStockPrices AS f
INNER JOIN dbo.DimCompany AS c
     ON f.Company_Key = c.CompanyKey
GROUP BY c.CompanyName
ORDER BY AverageDailyVolume DESC;


---Which company had the highest average daily price range??

SELECT 
    c.CompanyName,
    AVG(CAST(f.High_Price - f.Low_Price AS FLOAT)) AS AverageDailyPriceRange
    FROM dbo.FactStockPrices AS f
    INNER JOIN dbo.DimCompany AS c
        ON f.Company_Key = c.Companykey
GROUP BY c.CompanyName
ORDER BY AverageDailyPriceRange DESC;

---Which Sector generated the highest average company price return???

WITH FirstLast AS
(
  SELECT
       c.CompanyName,
       c.Sector,
       FIRST_VALUE(f.Close_Price) OVER(PARTITION BY c.CompanyKey ORDER BY d.Full_Date ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS FirstClose,
LAST_VALUE(f.Close_Price)
OVER(
      PARTITION BY c.CompanyKey
      ORDER BY d.Full_Date
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastClose
      FROM dbo.FactStockPrices AS f
      INNER JOIN dbo.DimCompany AS c
           ON f.Company_Key = c.CompanyKey
           INNER JOIN dbo.DimDate AS d
               ON f.Date_Key = d.Date_Key
               ),
CompanyReturns AS
(
  SELECT DISTINCT
  companyName,
  Sector,
  (LastClose - FirstClose)*100.0/NULLIF(FirstClose,0) AS ReturnPct
  FROM FirstLast 
  )
  SELECT
       Sector,
       AVG(Returnpct) AS
  AverageCompanyReturnPct
  FROM CompanyReturns
  GROUP BY Sector
  ORDER BY AverageCompanyReturnPct
  DESC;

  ---Which company had the largest single-day closing-price decline??
  WITH DailyReturns AS
  (
    SELECT
         c.CompanyName,
         d.Full_Date,
         f.Close_Price,
         LAG(f.Close_Price) OVER(PARTITION BY f.Company_Key ORDER BY d.Full_Date) AS PreviousClose
         FROM dbo.FactStockPrices  AS f
         INNER JOIN dbo.DimCompany AS c
         ON f.company_key = c.companykey
         INNER JOIN dbo.DimDate AS d
         ON f.Date_Key = d.Date_Key)
         SELECT TOP 1
         CompanyName,
         Full_Date,
         PreviousClose,
         Close_Price,
         CAST((close_Price - PreviousClose)*100.0/NULLIF(PreviousClose,0) AS DECIMAL(10,2)) AS DailyReturnPct
         FROM DailyReturns
         WHERE PreviousClose IS NOT NULL
         ORDER BY DailyReturnPct ASC;


--- Which Company reached its highest closing price??

WITH RankedPrices AS
(
  SELECT
       c.CompanyName,
       d.Full_Date,
       f.Close_Price,
       ROW_NUMBER() OVER(PARTITION BY f.Company_key ORDER BY f.Close_Price DESC, d.Full_Date DESC) AS rn
       FROM dbo.FactStockPrices AS f
       INNER JOIN dbo.DimCompany AS C
       ON f.Company_Key=c.CompanyKey
       INNER JOIN dbo.DimDate AS d
       ON f.Date_Key = d.Date_Key
       )
       SELECT
            CompanyName,
            Full_Date,
            close_Price
       FROM RankedPrices
       WHERE rn =1
       ORDER BY Close_Price DESC;

---
   

