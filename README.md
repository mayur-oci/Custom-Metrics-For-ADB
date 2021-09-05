# Configuring Custom Metrics for Oracle Autonomous Database, by leveraging Oracle Cloud Monitoring Service
## Introduction
[Oracle Autonomous Database](https://www.oracle.com/autonomous-database/)(ADB) is revolutionizing how data is managed with the introduction of the world’s first "self-driving" database. ADB is powering critical business applications of enterprises, all over the world, as their primary data source.

ADB provides many important database related [service metrics](https://docs.oracle.com/en-us/iaas/Content/Database/References/databasemetrics_topic-Overview_of_the_Database_Service_Autonomous_Database_Metrics.htm) out of the box, thanks to its deep integration with OCI Monitoring Service.
That being said, many our innovative customers wish to take their Observability journey a step further:
These **customers want to collect, publish and analyse their own metrics, related to the application data stored in the ADB**. In Oracle Monitoring Service terminology we call these [*custom metrics*](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Tasks/publishingcustommetrics.htm). These are the metrics which your applications can collect and post it to Oracle Monitoring Service, with simple REST API or OCI SDK.

In this tutorial, I will showcase how easily we can publish custom metrics from your ADB service, with just a few lines of PL/SQL script and few clicks on OCI Console! We, at Oracle Cloud believe in meeting customers where they are in their cloud journey!

This tutorial will use ecommerce shopping order database schema as an example; to showcase how we can compute, collect metrics on the this data. We will see how we can periodically compute metric representing count for each order-status(fullfilled, accepted, rejected etc) for each order that our ecommerece application receives. And finally we will post these custom metrics Oracle Cloud Monitoring Service.

Custom metrics metrics are first class citizens of Oracle Cloud Monitoring Service, on par with native metrics. You can analyse them with the same powerfull *Metrics Query Language* and setup Alarms on them to notify you whenever any event of interest or trouble happen.

## Prerequisites
### Infrastructure
1. Access to Oracle cloud free tier or paid account.
2. You can use any type of Oracle Autonomous Database Instance i.e.; shared or dedicated. For the tutorial though, Oracle Autonomous Transaction Processing(ATP) instance with just 1 OCPU and 1 TB of storage, is sufficient.

### Software Tools
1. Basic PL/SQL familiarity.
2. OCI Console familiarity.
3. If you are going to use SQL Developer or Other desktop clients, then you also need to know about [how to connect to ADB using Wallet](https://docs.oracle.com/en/cloud/paas/autonomous-data-warehouse-cloud/cswgs/autonomous-connect-sql-developer.html#GUID-14217939-3E8F-4782-BFF2-021199A908FD).  To make things easier, In the tutorial we are going to use, [SQL Developer Web](https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/sql-developer-web.html#GUID-C32A78E5-4C5F-476F-86AB-AEEEA9CF2704), available right from OCI Console page for ATP.
4. ADMIN user access to your ADB/ATP instance, incase you want to run the scripts of the tutorial, in new different DB schema other than the ADMIN. If you already have dedicated seperate schema, this requirenment can be skipped.
5. Basic familiarity with Oracle Cloud Concepts like [Monitoring Service](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Concepts/monitoringoverview.htm), [Dynamic Groups and Resouce Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Concepts/overview.htm).

## Solution at a glance:
![enter image description here](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_1_archi.png?raw=true)
As shown above we will have simple PL/SQL script deployed in our ADB instance,  which is scheduled run periodically to compute, collect & post the custom metrics Oracle Monitoring Service. Additionally ADB Service instance can be with private or public endpoint. Irrespective of that, the communication between ADB and Oracle Monitoring Service takes place on Oracle Cloud Network which is ultra fast and highly available. No need to setup Service Gateway.
*In this tutorial we are covering up-till getting the custom metrics from ADB to Oracle Monitoring Service. Please refer Oracle Cloud documentation and blogs to know more about, setting up Alarms, Notifications on Oracle Cloud Metrics is extensively covered*

## Overview of Steps
1. Create Dynamic Group for your ADB instance and authorize it to post metrics to *Oracle Cloud Monitoring Service* with policy.
2. Create new DB user/schema with requisite privilges in your ADB or update existing DB user/schema with requisite privilges.
4. Create table ***SHOPPING_ORDER***, to hold example data over which we will compute metrics.
5. Run example PL/SQL scripts to populate data in ***SHOPPING_ORDER*** table.
6. Schedule and run another PL/SQL scripts to compute, collect & post the custom metrics *Oracle Monitoring Service*.
   *Needless to say, in production usecase you will have your app doing the real world data population and updates. Hence steps 4 and 5 wont be needed in your production usecase.*
## Detailed Steps:
1. Create Dynamic Group for your ADB instance and authorize it to post metrics to *Oracle Cloud Monitoring Service* with policy.
    1. Create Dynamic Group named ***adb_dg*** for your ADB instance(or instances), with the rule say as

       `ALL {resource.type = 'autonomousdatabase', resource.compartment.id = '<compartment OCID for your ADB instance>'}`

       Alternatively you can just choose single ADB instance instead of all the instances in the compartment as

        `ALL {resource.type = 'autonomousdatabase', resource.id = '<OCID for your ADB instance>'}`	 

![enter image description here](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_2_dg.png?raw=true)
2. Create OCI IAM policy to authorize the dynamic group ***adb_dg*** , to post metrics to *Oracle Cloud Monitoring Service* with policy named ***adb_dg_policy***, with policy rules as
```plsql
   Allow dynamic-group adb_dg to read metrics in compartment <Your ADB Compartment OCID>
```

![width="80%"](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_3_policy.png?raw=true)

Now your ADB Service(covered by definition of your dynamic group adb_dg) is authorized to post metrics in the same compartment!
But no DB user is yet authorized to do it. Hence, effectively PL/SQL running on ADB can not still post any metrics to *Oracle Monitoring Service*. We will fix that in the steps, specifically 3.iii.

3. Create new DB user/schema with requisite privilges in your ADB or update existing DB user/schema with requisite privilges.

    1. Create new DB user/schema named ***ecommerce_user*** in your ADB. You can create this user as ADMIN user is created for every ADB instance. You can skip this step, if you choose to use existing user.
   ```plsql
      CREATE USER ECOMMERCE_USER IDENTIFIED BY "Password of your choice for this User";
   ```
   Now onwards we will refer to the user as simply ***ECOMMERCE_USER*** , as remaining the steps remain the same, whether it is existing user or newly created one.

    2. Grant requisite Oracle Database related privileges to the ***ECOMMERCE_USER***.
   ```plsql
      GRANT CREATE TABLE, ALTER ANY INDEX, CREATE PROCEDURE, CREATE JOB, 
              SELECT ANY TABLE, EXECUTE ANY PROCEDURE, 
              UPDATE ANY TABLE, CREATE SESSION,
              UNLIMITED TABLESPACE, CONNECT, RESOURCE TO ECOMMERCE_USER;
      GRANT SELECT ON "SYS"."V_$PDBS" TO ECOMMERCE_USER;
      GRANT EXECUTE ON "C##CLOUD$SERVICE"."DBMS_CLOUD" to ECOMMERCE_USER;
      GRANT EXECUTE on "SYS"."DBMS_LOCK" to ECOMMERCE_USER ;   
   ```       

    3. Enable Oracle DB credential for Oracle Cloud Resource Principal and give its access to db-user ECOMMERCE_USER. This basically connect the dyanmic group ***adb_dg*** we created in step 1 to our DB user ***ECOMMERCE_USER***, giving it the authorization to post metrics to *Oracle Cloud Monitoring Service*. For details, refer [Oracle Cloud Resource Principle For Autonomous Databases](https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/resource-principal.html).

    ```plsql
     EXEC DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(username => 'ECOMMERCE_USER');
     ```
 
     4.  This step is optional and here we just reverify the operations we did in previous step.
         Please note the Oracle DB credential corresponding to Oracle Cloud Resource Principal once enabled, is always owned by ADMIN user for ADB.  You can verify the same as follows.
      
    ```plsql
       SELECT OWNER, CREDENTIAL_NAME FROM DBA_CREDENTIALS WHERE CREDENTIAL_NAME =  'OCI$RESOURCE_PRINCIPAL'  AND OWNER =  'ADMIN';
       
       -- To check if any other user, here ECOMMERCE_USER has access DB credential(hence to OCI Resource Principal), you have to check *DBA_TAB_PRIVS* view, as follows.
       SELECT * from DBA_TAB_PRIVS WHERE DBA_TAB_PRIVS.GRANTEE='ECOMMERCE_USER';
   ```
   
4. Create example data table ***SHOPPING_ORDER*** to showcase computation of metrics on a database tables. You can create this table in newly created schema in step 2 or in already existing DB schema of your choice.
   The table schema is self-explanatory but please note status column. Each shopping order can have any of 8 status values during its lifetime namely: ACCEPTED','PAYMENT_REJECTED', 'SHIPPED', 'ABORTED',
   'OUT_FOR_DELIVERY', 'ORDER_DROPPED_NO_INVENTORY', 'PROCESSED', 'NOT_FULLFILLED'. 

   ```plsql
   CREATE TABLE SHOPPING_ORDER
   (
       ID                 NUMBER         GENERATED BY DEFAULT ON NULL AS IDENTITY PRIMARY KEY,
       CREATED_DATE       TIMESTAMP(6)   DEFAULT CURRENT_TIMESTAMP,
       DETAILS            VARCHAR2(1000) DEFAULT NULL,
       LAST_UPDATED_DATE  TIMESTAMP(6)   DEFAULT CURRENT_TIMESTAMP,
       STATUS             VARCHAR2(30 CHAR),
       TOTAL_CHARGES      FLOAT          DEFAULT 0.0,
       CUSTOMER_ID        NUMBER(19)     
   )
   PARTITION BY LIST(STATUS)
       (PARTITION ACCEPTED VALUES ('ACCEPTED'),
       PARTITION PAYMENT_REJECTED VALUES ('PAYMENT_REJECTED'),
       PARTITION SHIPPED VALUES('SHIPPED'),
       PARTITION ABORTED VALUES('ABORTED'),
       PARTITION OUT_FOR_DELIVERY VALUES('OUT_FOR_DELIVERY'),
       PARTITION ORDER_DROPPED_NO_INVENTORY VALUES('ORDER_DROPPED_NO_INVENTORY'),
       PARTITION PROCESSED VALUES('PROCESSED'),
       PARTITION NOT_FULLFILLED VALUES('NOT_FULLFILLED')
       );
   
       -- we move rows from one partition to another, hence we enable row movement for this partioned table
   ALTER TABLE SHOPPING_ORDER ENABLE ROW MOVEMENT;
   /
   ```
5. Run the following PL/SQL scripts with the necessary stored procedures to populate data in ***SHOPPING_ORDER*** table. The script will keep on first adding 10000 rows into ***SHOPPING_ORDER*** table with random data and then it will update the same data.
Script will run approximately for 20 minutes on ATP with 1 OCPU with 1TB storage.   
   ```plsql
    CREATE OR REPLACE PROCEDURE populate_data_feed IS
    arr_status_random_index INTEGER;
    customer_id_random INTEGER;
    type STATUS_ARRAY IS VARRAY(8) OF VARCHAR2(30);
    array STATUS_ARRAY := STATUS_ARRAY('ACCEPTED','PAYMENT_REJECTED', 'SHIPPED', 'ABORTED',
    'OUT_FOR_DELIVERY', 'ORDER_DROPPED_NO_INVENTORY',
    'PROCESSED', 'NOT_FULLFILLED');
    total_rows_in_shopping_order INTEGER := 10000;
    
    type rowid_nt is table of rowid;
    rowids rowid_nt;
    BEGIN     
    -- starting from scratch just be idempotent and have predictable execution time for this stored procedure
    -- deleting existing rows is optional
    DELETE SHOPPING_ORDER;
    
    -- insert data
    FOR counter IN 1..total_rows_in_shopping_order LOOP
    arr_status_random_index := TRUNC(dbms_random.value(low => 1, high => 9));
    customer_id_random := TRUNC(dbms_random.value(low => 1, high => 8000));
    INSERT INTO SHOPPING_ORDER(STATUS, CUSTOMER_ID)
    VALUES(array(arr_status_random_index), customer_id_random);
    COMMIT;          
    --DBMS_LOCK.SLEEP(1);          
    END LOOP;
    dbms_output.put_line('Done with initial data load');
    
    -- keep on updating the same data
    FOR counter IN 1..10000 LOOP
    
                --Get the rowids
                SELECT r bulk collect into rowids
                FROM (
                    SELECT ROWID r
                    FROM SHOPPING_ORDER sample(5)
                    ORDER BY dbms_random.value
                )RNDM WHERE rownum < total_rows_in_shopping_order+1;
                
                --update the table
                arr_status_random_index := TRUNC(dbms_random.value(low => 1, high => 9));
                for i in 1 .. rowids.count LOOP
                    update SHOPPING_ORDER SET STATUS=array(arr_status_random_index)
                    where rowid = rowids(i);
                    COMMIT;          
                END LOOP;    
                --sleep in-between if you want to run script for longer duration
                --DBMS_LOCK.SLEEP(ROUND(dbms_random.value(low => 1, high => 2)));          
    END LOOP;
    dbms_output.put_line('Done with data feed');
    
    EXECUTE IMMEDIATE 'ANALYZE TABLE SHOPPING_ORDER COMPUTE STATISTICS';
    
    END;
    /
    
    -- we schedule the data feed since we want it to run right now but asychronously
    BEGIN
    DBMS_SCHEDULER.CREATE_JOB
    (  
    JOB_NAME      =>  'POPULATE_DATA_FEED',  
    JOB_TYPE      =>  'STORED_PROCEDURE',  
    JOB_ACTION    =>  'POPULATE_DATA_FEED',  
    ENABLED       =>  TRUE,  
    AUTO_DROP     =>  TRUE,  
    COMMENTS      =>  'ONE-TIME JOB');
    END;
    /
    
    -- just for our information
    SELECT STATUS,count(*) FROM SHOPPING_ORDER GROUP BY STATUS;   
   ```

6. Now let us  
