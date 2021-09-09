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
2. You can use any type of Oracle Autonomous Database Instance i.e.; shared or dedicated. 

   For the tutorial though, Oracle Autonomous Transaction Processing(ATP) instance with just 1 OCPU and 1 TB of storage, is sufficient.

### Software Tools
1. Basic PL/SQL familiarity.
2. OCI Console familiarity.
3. You can use any of Oracle DB clients like SQL Developer or SQL*Plus. If you are new to ADB please see [how to connect to ADB using Wallet](https://docs.oracle.com/en/cloud/paas/autonomous-data-warehouse-cloud/cswgs/autonomous-connect-sql-developer.html#GUID-14217939-3E8F-4782-BFF2-021199A908FD).  
   For ATPs we also have [SQL Developer Web](https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/sql-developer-web.html#GUID-C32A78E5-4C5F-476F-86AB-AEEEA9CF2704), available right from OCI Console page for ATP, with no need of wallet. 
4. ADMIN user access to your ATP instance.
5. Basic familiarity with Oracle Cloud Concepts like [Monitoring Service](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Concepts/monitoringoverview.htm), [PostMetrics api for publishing custom metrics](https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData) 
   & [Dynamic Groups and Resource Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Concepts/overview.htm).

## Solution at a glance:
![enter image description here](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_1_archi.png?raw=true)
>As shown above we will have simple PL/SQL script deployed in our ADB instance,  which is scheduled run periodically to compute, collect & post the custom metrics Oracle Monitoring Service. 
>>Additionally, ADB Service instance can be with private or public endpoint. Irrespective of that, the communication between ADB and Oracle Monitoring Service takes place on Oracle Cloud Network which is ultra fast and highly available. No need to setup Service Gateway.

>>In this tutorial we are covering up-till getting the custom metrics from ADB to Oracle Monitoring Service. Please refer Oracle Cloud documentation and blogs to know more about, setting up Alarms, Notifications on Oracle Cloud Metrics is extensively covered.

## Overview of Steps
1. Create Dynamic Group for your ADB instance and authorize it to post metrics to *Oracle Cloud Monitoring Service* with policy.
2. Create new DB user/schema with requisite privileges in your ADB or update existing DB user/schema with requisite privileges.
3. Create table named `SHOPPING_ORDER`, for storing data for our example ecommerce app. 
<br>We compute custom metrics on the customer-orders stored in this table.
5. Run PL/SQL scripts to populate random data of customer-orders in `SHOPPING_ORDER` table.
6. Schedule and run another PL/SQL script to compute, collect/buffer & post the custom metrics *Oracle Monitoring Service*.

>   Needless to say, in production use-case you will have your own application doing the real world data population and updates. 
   Hence, steps 4 and 5 won't be needed in your production use-case.

## Detailed Steps:
1. Create Dynamic Group for your ADB instance and authorize it to post metrics to *Oracle Cloud Monitoring Service* with policy.
    1. Create Dynamic Group named `adb_dg` for your ADB instance(or instances), with the rule say as

       `ALL {resource.type = 'autonomousdatabase', resource.compartment.id = '<compartment OCID for your ADB instance>'}`

       Alternatively you can just choose single ADB instance instead of all the instances in the compartment as

        `ALL {resource.type = 'autonomousdatabase', resource.id = '<OCID for your ADB instance>'}`	 

      ![enter image description here](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_2_dg.png?raw=true)
    2. Create OCI IAM policy to authorize the dynamic group ***adb_dg*** , to post metrics to *Oracle Cloud Monitoring Service* with policy named `adb_dg_policy`, with policy rules as </br>
    `Allow dynamic-group adb_dg to read metrics in compartment <Your ADB Compartment OCID>`
    </br> Same is shown as below.

    ![width="80%"](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_3_policy.png?raw=true)

    Now your ATP Service(covered by definition of your dynamic group `adb_dg`) is authorized to post metrics in the same compartment!
    >But no ATP DB user is yet authorized to publish metrics to *Oracle Cloud Monitoring Service*. Hence, effectively PL/SQL running on ADB can not still post any metrics to *Oracle Cloud Monitoring Service*. We will fix that in the steps, specifically 3.iii.

   
2. Create new DB user/schema with requisite privileges in your ADB or update existing DB user/schema with requisite privileges.

    1. Create new DB user/schema named `ECOMMERCE_USER` in your ADB. You can create this user as ADMIN user is created for every ADB instance. You can skip this step, if you choose to use existing user.
   ```plsql
      CREATE USER ECOMMERCE_USER IDENTIFIED BY "Password of your choice for this User";
   ```
   Now onwards we will refer to the user(or schema) as simply `ECOMMERCE_USER` , as remaining the steps remain the same, whether it is existing user or newly created one.

    2. Grant requisite Oracle Database related privileges to the `ECOMMERCE_USER`.
   ```plsql
      GRANT CREATE TABLE, ALTER ANY INDEX, CREATE PROCEDURE, CREATE JOB, 
              SELECT ANY TABLE, EXECUTE ANY PROCEDURE, 
              UPDATE ANY TABLE, CREATE SESSION,
              UNLIMITED TABLESPACE, CONNECT, RESOURCE TO ECOMMERCE_USER;
      GRANT SELECT ON "SYS"."V_$PDBS" TO ECOMMERCE_USER;
      GRANT EXECUTE ON "C##CLOUD$SERVICE"."DBMS_CLOUD" to ECOMMERCE_USER;
      GRANT SELECT ON SYS.DBA_JOBS_RUNNING TO ECOMMERCE_USER;
   ```       

    3. Enable Oracle DB credential for Oracle Cloud Resource Principal and give its access to db-user ECOMMERCE_USER. This basically connect the dyanmic group ***adb_dg*** we created in step 1 to our DB user ***ECOMMERCE_USER***, giving it the authorization to post metrics to *Oracle Cloud Monitoring Service*. For details, refer [Oracle Cloud Resource Principle For Autonomous Databases](https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/resource-principal.html).

    ```plsql
     EXEC DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(username => 'ECOMMERCE_USER');
     ```
 
     4. This step is optional and here we just verify the operations we did in previous step.
         Please note the Oracle DB credential corresponding to Oracle Cloud Resource Principal once enabled, is always owned by ADMIN user for ADB.  
         You can verify the same as follows.
      
    ```plsql
       SELECT OWNER, CREDENTIAL_NAME FROM DBA_CREDENTIALS WHERE CREDENTIAL_NAME =  'OCI$RESOURCE_PRINCIPAL'  AND OWNER =  'ADMIN';
       
       -- To check if any other user, here ECOMMERCE_USER has access DB credential(hence to OCI Resource Principal), you have to check *DBA_TAB_PRIVS* view, as follows.
       SELECT * from DBA_TAB_PRIVS WHERE DBA_TAB_PRIVS.GRANTEE='ECOMMERCE_USER';
    ```
   
3. Create example data table `SHOPPING_ORDER` to showcase computation of metrics on a database tables. 

   You can create this table in newly created schema in step 2 or in already existing DB schema of your choice.
   The table schema is self-explanatory but please take a note status column.

   ```plsql
    DROP TABLE SHOPPING_ORDER;
    CREATE TABLE SHOPPING_ORDER (
        ID                NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
        PRIMARY KEY,
        CREATED_DATE      TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP,
        DETAILS           VARCHAR2(1000) DEFAULT NULL,
        LAST_UPDATED_DATE TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP,
        STATUS            VARCHAR2(30 CHAR),
        TOTAL_CHARGES     FLOAT DEFAULT 0.0,
        CUSTOMER_ID       NUMBER(19)
    )
        PARTITION BY LIST ( STATUS ) 
        (   PARTITION ACCEPTED VALUES ( 'ACCEPTED' ),
            PARTITION PAYMENT_REJECTED VALUES ( 'PAYMENT_REJECTED' ),
            PARTITION SHIPPED VALUES ( 'SHIPPED' ),
            PARTITION ABORTED VALUES ( 'ABORTED' ),
            PARTITION OUT_FOR_DELIVERY VALUES ( 'OUT_FOR_DELIVERY' ),
            PARTITION ORDER_DROPPED_NO_INVENTORY VALUES ( 'ORDER_DROPPED_NO_INVENTORY' ),
            PARTITION PROCESSED VALUES ( 'PROCESSED' ),
            PARTITION NOT_FULLFILLED VALUES ( 'NOT_FULLFILLED' )
        );
    /
   
    -- we move rows from one partition to another, hence we enable row movement for this partioned table
    ALTER TABLE SHOPPING_ORDER ENABLE ROW MOVEMENT;
   ```
   Each shopping order can have any of 8 `status` values during its lifetime namely:
   `[ACCEPTED,PAYMENT_REJECTED, SHIPPED, ABORTED,
   OUT_FOR_DELIVERY, ORDER_DROPPED_NO_INVENTORY,
   PROCESSED, NOT_FULFILLED]`.

4. Read through the following PL/SQL script. It has all the necessary stored procedures to populate data in ***SHOPPING_ORDER*** table. The script will keep on first adding 10000 rows into ***SHOPPING_ORDER*** table with random data and then it will update the same data.
Script will run approximately for 20 minutes on ATP with 1 OCPU with 1TB storage.   
   ```plsql
    CREATE OR REPLACE PROCEDURE POPULATE_DATA_FEED IS
        ARR_STATUS_RANDOM_INDEX      INTEGER;
        CUSTOMER_ID_RANDOM           INTEGER;
        TYPE STATUS_ARRAY IS VARRAY(8) OF VARCHAR2(30);
        ARRAY STATUS_ARRAY := STATUS_ARRAY('ACCEPTED', 'PAYMENT_REJECTED',
                                        'SHIPPED', 'ABORTED', 'OUT_FOR_DELIVERY',
                                        'ORDER_DROPPED_NO_INVENTORY', 
                                        'PROCESSED', 'NOT_FULFILLED');
        TOTAL_ROWS_IN_SHOPPING_ORDER INTEGER := 10000;
        TYPE ROWID_NT IS TABLE OF ROWID;
        ROWIDS                       ROWID_NT;
    BEGIN     
        -- starting from scratch just be idempotent and have predictable execution time for this stored procedure
        -- deleting existing rows is optional 
        DELETE SHOPPING_ORDER;
    
        -- insert data
        FOR COUNTER IN 1..TOTAL_ROWS_IN_SHOPPING_ORDER LOOP
            ARR_STATUS_RANDOM_INDEX := TRUNC(DBMS_RANDOM.VALUE(LOW => 1, HIGH => 9));
            CUSTOMER_ID_RANDOM := TRUNC(DBMS_RANDOM.VALUE(LOW => 1, HIGH => 8000));
            INSERT INTO SHOPPING_ORDER (STATUS,CUSTOMER_ID) VALUES (ARRAY(ARR_STATUS_RANDOM_INDEX),CUSTOMER_ID_RANDOM);
            COMMIT;          
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('DONE WITH INITIAL DATA LOAD');

        -- keep on updating the same data
        FOR COUNTER IN 1..7000 LOOP        
                
                --Get the rowids
            SELECT R BULK COLLECT INTO ROWIDS FROM (SELECT ROWID R FROM SHOPPING_ORDER SAMPLE ( 5 ) ORDER BY DBMS_RANDOM.VALUE) RNDM
            WHERE ROWNUM < TOTAL_ROWS_IN_SHOPPING_ORDER + 1;
                
                --update the table
            ARR_STATUS_RANDOM_INDEX := TRUNC(DBMS_RANDOM.VALUE(LOW => 1, HIGH => 9));

            FOR I IN 1..ROWIDS.COUNT LOOP
                UPDATE SHOPPING_ORDER SET STATUS = ARRAY(ARR_STATUS_RANDOM_INDEX) WHERE ROWID = ROWIDS(I);
                COMMIT;
            END LOOP;    
            --sleep in-between if you want to run script for longer duration
            --DBMS_SESSION.SLEEP(ROUND(dbms_random.value(low => 1, high => 2)));          
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('DONE WITH POPULATE_DATA_FEED');
        EXECUTE IMMEDIATE 'ANALYZE TABLE SHOPPING_ORDER COMPUTE STATISTICS';
    END;
    /

    -- we schedule the data feed since we want it to run right now but asychronously
    BEGIN
        DBMS_SCHEDULER.CREATE_JOB(JOB_NAME => 'POPULATE_DATA_FEED_JOB', 
                                JOB_TYPE => 'STORED_PROCEDURE', 
                                JOB_ACTION => 'POPULATE_DATA_FEED',
                                ENABLED => TRUE, 
                                AUTO_DROP => TRUE, -- drop job after 1 run.
                                COMMENTS => 'ONE-TIME JOB');
    END;
    /
       
    -- just for our information
    SELECT STATUS,count(*) FROM SHOPPING_ORDER GROUP BY STATUS;   
   ```

5. Now let us dive deep into actual crux of this tutorial: script which computes the custom metrics and publishes it to Oracle Cloud Monitoring Service.
   


  ```plsql

   
       
   ```

   We will analyse the above script in topdown fashion, going from publishing the computed custom metrics then to their actual computation.
   The stored procedure `post_metrics_to_oci` is the piece of code which first computes the metric value and 
   then actually invokes the [PostMetricsData API](https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData), to publish these custom metrics Oracle Cloud Monitoring Service.
   
   As with every Oracle Cloud API, you need proper IAM authorization to invoke it. We pass the same as follows, with the named parameter `credential_name => 'OCI$RESOURCE_PRINCIPAL'`. 
   The DB credential `OCI$RESOURCE_PRINCIPAL` is linked to dynamic group `adb_dg` we created earlier in step 2 and user `ECOMMERCE_USER` already has access to the same, from step 3. 
   Hence by *chain of trust*, this PL/SQL script executed by `ECOMMERCE_USER` has authorization to post the custom metrics to Oracle Monitoring Service. 
   ```plsql
            resp := dbms_cloud.send_request(
                    credential_name => 'OCI$RESOURCE_PRINCIPAL',
                    uri => 'https://telemetry-ingestion.' || adb_region || '.oraclecloud.com/20180401/metrics',
                    method => dbms_cloud.METHOD_POST,
                    body => UTL_RAW.cast_to_raw(oci_post_metrics_body_json_obj.to_string));   
   ```
   `dbms_cloud.send_request` is an inbuilt PL/SQL stored procedure invoke any rest endpoint, preinstalled with every ADB. Here we are using it to invoke Oracle Cloud Monitoring Service REST API.
   [PostMetricsData API](https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData) expects JSON body of the type [PostMetricDataDetails](https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/datatypes/PostMetricDataDetails). 
   We create this JSON with variable `oci_post_metrics_body_json_obj` of PL/SQL inbuilt datatype `json_object_t`. This enables us to easily create complex JSONs with strong safety PL/SQL type system.

   We need to know region of this ADB instance to determine Oracle Monitoring Service endpoint for this region. We fetch this meta-data from view `V$PDBS` along with other information like compartmentId and DBName for this ADB. 
   This information acts as dimensions and metadata information for our custom metrics, helping us to correlate these custom metrics with our ADB Instance Service. 
  
   
   

