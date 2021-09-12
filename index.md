# Publishing Custom Metrics from Oracle Autonomous Database, by leveraging Oracle Cloud Monitoring Service
## Introduction
[Oracle Autonomous Database](https://www.oracle.com/autonomous-database/)(ADB) is revolutionizing how data is managed with the introduction of the world’s first "self-driving" database. ADB is powering critical business applications of enterprises, all over the world, as their primary data source.

ADB provides many important database related [service metrics](https://docs.oracle.com/en-us/iaas/Content/Database/References/databasemetrics_topic-Overview_of_the_Database_Service_Autonomous_Database_Metrics.htm) out of the box, thanks to its deep integration with OCI Monitoring Service.
That being said, many our innovative customers wish to take their Observability journey a step further:
These **customers want to collect, publish and analyse their own metrics, related to the application data stored in the ADB**. In Oracle Monitoring Service terminology we call these [*custom metrics*](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Tasks/publishingcustommetrics.htm). These are the metrics which your applications can collect and post it to Oracle Monitoring Service, with simple REST API provided by OCI SDK.

In this tutorial, I will showcase how easily we can publish custom metrics from your ADB service, with few PL/SQL scripts and few clicks on OCI Console! We, at Oracle Cloud believe in meeting customers where they are in their cloud journey!

This tutorial will use ecommerce shopping order database schema as an example; to showcase how we can compute, collect metrics on this data. We will see how we can periodically compute metric representing count for each order-status(fulfilled, accepted, rejected etc.) for each order that our ecommerce application receives. And finally we will publish these custom metrics *Oracle Cloud Monitoring Service*.

## Prerequisites
### Infrastructure
1. Access to Oracle cloud free tier or paid account.
2. You can use any type of Oracle Autonomous Database Instance i.e.; shared or dedicated.
   > For the tutorial, we use Oracle Autonomous Database for Transaction Processing(ATP) instance, with just 1 OCPU and 1 TB of storage, on shared infrastructure. 
   You can create it with Oracle cloud free tier account.

### Other
1. Basic PL/SQL familiarity.
2. Oracle Cloud Console familiarity.
3. You can use any of Oracle DB clients like SQL Developer or SQL*Plus. 
   If you are new to ATP please see [how to connect to ATP using Wallet](https://docs.oracle.com/en-us/iaas/Content/Database/Tasks/adbconnecting.htm#about).  
   > For ATPs we also have [*SQL Developer Web*](https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/sql-developer-web.html#GUID-C32A78E5-4C5F-476F-86AB-AEEEA9CF2704), 
   available right from OCI Console page for ATP. There is no need of wallet when using *SQL Developer Web*. 
4. `ADMIN` user access to your ATP instance.
5. Basic familiarity with Oracle Cloud Concepts like [Monitoring Service](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Concepts/monitoringoverview.htm), [PostMetrics api for publishing custom metrics](https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData) 
   & [Dynamic Groups and Resource Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Concepts/overview.htm).

## Solution at a glance:
![enter image description here](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_1_archi.png?raw=true)
>As shown above we will have simple PL/SQL script deployed in our ADB instance,  which is scheduled run periodically to compute, collect & post the custom metrics Oracle Cloud Monitoring Service. 
>>Additionally, ADB Service instance can be with private or public endpoint. Irrespective of that, the communication between ADB and Oracle Cloud Monitoring Service takes place on Oracle Cloud Network which is ultra-fast and highly available. No need to set up Service Gateway.

>>In this tutorial we are covering up-till getting the custom metrics from ADB to Oracle Cloud Monitoring Service.

## Overview of Steps
1. Create Dynamic Group for your ATP instance and authorize it to post metrics to *Oracle Cloud Monitoring Service* with policy.
2. Create new DB user/schema with requisite privileges in your ATP or update existing DB user/schema with requisite privileges.
3. Create table named `SHOPPING_ORDER`, for storing data for our example ecommerce app. 
<br>We compute custom metrics on the customer-orders stored in this table.
4. Peruse PL/SQL script to populate random data of customer-orders in `SHOPPING_ORDER` table.
5. Peruse PL/SQL script to compute, collect/buffer & post the custom metrics *Oracle Monitoring Service*.
6. Schedule and run scripts from step 4 & 5.
7. Observe the published custom metrics on *Oracle Cloud Web Console*.

>   Needless to say, in production use-case you will have your own application doing the real world data population and updates. 
   Hence, steps 3 and 4 won't be needed in your production use-case.

## Detailed Steps:
1. Create Dynamic Group for your ATP instance and authorize it to post metrics to *Oracle Cloud Monitoring Service* with policy.
    1. Create Dynamic Group named `adb_dg` for your ATP instance(or instances), with the rule say as

       `ALL {resource.type = 'autonomousdatabase', resource.compartment.id = '<compartment OCID for your ADB instance>'}`

       Alternatively you can just choose single ATP instance instead of all the instances in the compartment as

        `ALL {resource.type = 'autonomousdatabase', resource.id = '<OCID for your ATP instance>'}`   

      ![enter image description here](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_2_dg.png?raw=true)
    2. Create OCI IAM policy to authorize the dynamic group ***adb_dg*** , to post metrics to *Oracle Cloud Monitoring Service* with policy named `adb_dg_policy`, with policy rules as </br>
    `Allow dynamic-group adb_dg to read metrics in compartment <Your ADB Compartment OCID>`
    </br> Same is shown as below.

    ![width="80%"](https://github.com/mayur-oci/adb_custom_metrics/blob/main/images/adb_3_policy.png?raw=true)

    Now your ATP Service(covered by definition of your dynamic group `adb_dg`) is authorized to post metrics in the same compartment!
    >But no ATP DB user is yet authorized to publish metrics to *Oracle Cloud Monitoring Service*. Hence, effectively PL/SQL running on ATP can not still post any metrics to *Oracle Cloud Monitoring Service*. We will fix that in the steps, specifically 3.iii.

   
2. Create new DB user/schema with requisite privileges in your ATP or update existing DB user/schema with requisite privileges.

    1. Create new DB user/schema named `ECOMMERCE_USER` in your ATP. You can create this user as ADMIN user is created for every ATP instance. You can skip this step, if you choose to use existing user.
   ```plsql
      CREATE USER ECOMMERCE_USER IDENTIFIED BY "Password of your choice for this User";
   ```
   Now onwards we will refer to the user(or schema) as simply `ECOMMERCE_USER` , as remaining the steps remain the same, whether it is existing user or newly created one.

    2. Grant requisite Oracle Database related privileges to the `ECOMMERCE_USER`.
   ```plsql
      GRANT  CREATE TABLE, ALTER ANY INDEX, CREATE PROCEDURE, CREATE JOB, 
             SELECT ANY TABLE, EXECUTE ANY PROCEDURE, 
             UPDATE ANY TABLE, CREATE SESSION,
             UNLIMITED TABLESPACE, CONNECT, RESOURCE TO ECOMMERCE_USER;
      GRANT  SELECT ON "SYS"."V_$PDBS" TO ECOMMERCE_USER;
      GRANT  EXECUTE ON "C##CLOUD$SERVICE"."DBMS_CLOUD" to ECOMMERCE_USER;
      GRANT  SELECT ON SYS.DBA_JOBS_RUNNING TO ECOMMERCE_USER;
   ```       

    3. Enable Oracle DB credential for Oracle Cloud Resource Principal and give its access to db-user ECOMMERCE_USER. This basically connect the *dynamic group* `adb_dg` we created in step 1 to our DB user `ECOMMERCE_USER`, giving it the authorization to post metrics to *Oracle Cloud Monitoring Service*. For details, refer [Oracle Cloud Resource Principle For Autonomous Databases](https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/resource-principal.html).
    
   ```plsql
     EXEC DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(username => 'ECOMMERCE_USER');
   ```
 
   4. This step is optional and here we just verify the operations we did in previous step.
      Please note the Oracle DB credential corresponding to Oracle Cloud Resource Principal once enabled, is always owned by ADMIN user for ADB. You can verify the same as follows.

    ```plsql
     SELECT OWNER, CREDENTIAL_NAME FROM DBA_CREDENTIALS WHERE CREDENTIAL_NAME =  'OCI$RESOURCE_PRINCIPAL'  AND OWNER =  'ADMIN';
       
     -- To check if any other user, here ECOMMERCE_USER has access DB credential(hence to OCI Resource Principal), you have to check *DBA_TAB_PRIVS* view, as follows.
     SELECT * from DBA_TAB_PRIVS WHERE DBA_TAB_PRIVS.GRANTEE='ECOMMERCE_USER';
    ```
   
3. Create example data table `SHOPPING_ORDER` to showcase computation of metrics on a database tables.</br>
   The table schema is self-explanatory but please take a note `STATUS` column.

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
            PARTITION NOT_FULLFILLED VALUES ( 'NOT_FULFILLED' )
        );
    /
   
    -- we move rows from one partition to another, hence we enable row movement for this partioned table
    ALTER TABLE SHOPPING_ORDER ENABLE ROW MOVEMENT;
   ```
   Each shopping order can have any of 8 `status` values during its lifetime namely:
   `[ACCEPTED,PAYMENT_REJECTED, SHIPPED, ABORTED,
   OUT_FOR_DELIVERY, ORDER_DROPPED_NO_INVENTORY,
   PROCESSED, NOT_FULFILLED]`.


4. Read through the following PL/SQL script. It populates data in `SHOPPING_ORDER` table. </br>
   The script will keep on first adding `TOTAL_ROWS_IN_SHOPPING_ORDER` number of rows into `SHOPPING_ORDER` table with randomly generated order data.</br> It then will update the same data, changing the `STATUS` values of each `SHOPPING_ORDER` row randomly.
   ```plsql
    CREATE OR REPLACE PROCEDURE POPULATE_DATA_FEED IS
        ARR_STATUS_RANDOM_INDEX      INTEGER;
        CUSTOMER_ID_RANDOM           INTEGER;
        TYPE STATUS_ARRAY IS VARRAY(8) OF VARCHAR2(30);
        ARRAY STATUS_ARRAY := STATUS_ARRAY('ACCEPTED', 'PAYMENT_REJECTED',
                                        'SHIPPED', 'ABORTED', 'OUT_FOR_DELIVERY',
                                        'ORDER_DROPPED_NO_INVENTORY', 
                                        'PROCESSED', 'NOT_FULFILLED');
        TOTAL_ROWS_IN_SHOPPING_ORDER INTEGER := 15000;
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
        FOR COUNTER IN 1..8000 LOOP        
                
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
   ```

5. Let us dive deep into actual crux of this tutorial: script which computes the custom metrics and publishes it to *Oracle Cloud Monitoring Service*.
   The script is idempotent to make sure you can play with it multiple runs. 
   Now, we will analyse the script piecemeal.
   1. We create table `SHOPPING_ORDER_METRICS_TABLE` and use it to collect/buffer computed metrics.</br>
   > Make sure your data tables are optimized for queries running metrics computation. You do not want these queries putting to load on your database, disturbing your production use-cases.

   ```plsql
    DECLARE
        COUNT_VAR NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO COUNT_VAR FROM ALL_TABLES WHERE TABLE_NAME = 'SHOPPING_ORDER_METRICS_TABLE';

        IF COUNT_VAR > 0 THEN
            DBMS_OUTPUT.PUT_LINE('TABLE EXISTS ALREADY!');
        ELSE
            -- table doesn't exist
            EXECUTE IMMEDIATE 'CREATE TABLE SHOPPING_ORDER_METRICS_TABLE(
                                ID                 NUMBER         GENERATED BY DEFAULT ON NULL AS IDENTITY PRIMARY KEY,
                                CREATED_DATE       TIMESTAMP(6)   DEFAULT CURRENT_TIMESTAMP,
                                STATUS             VARCHAR2(30 CHAR),
                                COUNT              NUMBER)';
        END IF;

    END;
    /
   ```
   

   2. Let us create a stored procedure which computes the metric: *Count for number of Orders by Status values, at the time instance of this metrics collection*.</br> 
      The stored procedure then buffers the computed metrics in our buffer table `SHOPPING_ORDER_METRICS_TABLE` created in previous step.
      We buffer to make sure, in-case of temporary interruption when publishing the metrics to *Oracle Cloud Monitoring Service*, we can retry posting them again in the future.

   ```plsql
    CREATE OR REPLACE PROCEDURE COMPUTE_AND_BUFFER_METRICS IS
    BEGIN    
        -- compute simple metric for getting count order by order-status 
        -- and store in buffer table SHOPPING_ORDER_METRICS_TABLE
        INSERT INTO SHOPPING_ORDER_METRICS_TABLE (STATUS, COUNT, CREATED_DATE) 
        SELECT STATUS, COUNT(*), SYSTIMESTAMP AT TIME ZONE 'UTC' FROM SHOPPING_ORDER SO GROUP BY SO.STATUS;
        
        -- we buffer at most 1000 metric points, please configure as per your needs
        DELETE FROM SHOPPING_ORDER_METRICS_TABLE SOMT WHERE SOMT.ID NOT IN
            (SELECT ID FROM SHOPPING_ORDER_METRICS_TABLE ORDER BY CREATED_DATE FETCH FIRST 1000 ROWS ONLY);
        
        COMMIT;    
        DBMS_OUTPUT.PUT_LINE('compute and buffering done @ ' || TO_CHAR(SYSTIMESTAMP));
    END;
    /
   ```
      In order to limit the size of buffer table, we trim it, if its size crosses 1000 rows.

   3. We now need function which converts buffered metrics from `SHOPPING_ORDER_METRICS_TABLE` into JSON objects that [PostMetricsData API](https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData) expects in its request.
      This is exactly what PL/SQL function `PREPARE_JSON_OBJECT_FROM_METRIC_ROWS` performs. 
      This function converts `BATCH_SIZE_FOR_EACH_POST` number of recent most metrics data-points from `SHOPPING_ORDER_METRICS_TABLE` into `OCI_METADATA_JSON_OBJ JSON_OBJECT_T`.
      
      `OCI_METADATA_JSON_OBJ` is variable of PL/SQL inbuilt JSON datatype `JSON_OBJECT_T`. 
      We have constructed `OCI_METADATA_JSON_OBJ` with same JSON structure as per [PostMetricDataDetails](https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/datatypes/PostMetricDataDetails), the request body for PostMetricsData API. 

   ```plsql
    CREATE OR REPLACE FUNCTION GET_METRIC_DATA_DETAILS_JSON_OBJ (
        IN_ORDER_STATUS         IN VARCHAR2,
        IN_METRIC_CMPT_ID       IN VARCHAR2,
        IN_ADB_NAME             IN VARCHAR2,
        IN_METRIC_VALUE         IN NUMBER,
        IN_TS_METRIC_COLLECTION IN VARCHAR2
    ) RETURN JSON_OBJECT_T IS
        METRIC_DATA_DETAILS JSON_OBJECT_T;
        MDD_METADATA        JSON_OBJECT_T;
        MDD_DIMENSIONS      JSON_OBJECT_T;
        ARR_MDD_DATAPOINT   JSON_ARRAY_T;
        MDD_DATAPOINT       JSON_OBJECT_T;
    BEGIN
        MDD_METADATA := JSON_OBJECT_T();
        MDD_METADATA.PUT('unit', 'row_count'); -- metric unit is arbitrary, as per choice of developer

        MDD_DIMENSIONS := JSON_OBJECT_T();
        MDD_DIMENSIONS.PUT('dbname', IN_ADB_NAME);
        MDD_DIMENSIONS.PUT('schema_name', SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
        MDD_DIMENSIONS.PUT('table_name', 'SHOPPING_ORDER');
        MDD_DIMENSIONS.PUT('status_enum', IN_ORDER_STATUS);
        MDD_DATAPOINT := JSON_OBJECT_T();
        MDD_DATAPOINT.PUT('timestamp', IN_TS_METRIC_COLLECTION); --timestamp value RFC3339 compliant
        MDD_DATAPOINT.PUT('value', IN_METRIC_VALUE);
        MDD_DATAPOINT.PUT('count', 1);
        ARR_MDD_DATAPOINT := JSON_ARRAY_T();
        ARR_MDD_DATAPOINT.APPEND(MDD_DATAPOINT);
        METRIC_DATA_DETAILS := JSON_OBJECT_T();
        METRIC_DATA_DETAILS.PUT('datapoints', ARR_MDD_DATAPOINT);
        METRIC_DATA_DETAILS.PUT('metadata', MDD_METADATA);
        METRIC_DATA_DETAILS.PUT('dimensions', MDD_DIMENSIONS);

        -- namespace, resourceGroup and name for the custom metric are arbitrary values, as per choice of developer
        METRIC_DATA_DETAILS.PUT('namespace', 'custom_metrics_from_adb');
        METRIC_DATA_DETAILS.PUT('resourceGroup', 'ecommerece_adb');
        METRIC_DATA_DETAILS.PUT('name', 'customer_orders_submitted');
       
        -- since compartment OCID is fetched using ADB metadata, our custom metrics will land up in same compartment as our ADB
        METRIC_DATA_DETAILS.PUT('compartmentId', IN_METRIC_CMPT_ID);
        RETURN METRIC_DATA_DETAILS;
    END;
    /

    CREATE OR REPLACE FUNCTION PREPARE_JSON_OBJECT_FROM_METRIC_ROWS (
        OCI_METADATA_JSON_OBJ JSON_OBJECT_T, BATCH_SIZE_FOR_EACH_POST NUMBER
    ) RETURN JSON_OBJECT_T IS
        OCI_POST_METRICS_BODY_JSON_OBJ JSON_OBJECT_T;
        ARR_METRIC_DATA                JSON_ARRAY_T;
        METRIC_DATA_DETAILS            JSON_OBJECT_T;
    BEGIN
        -- prepare JSON body for postmetrics api..
        -- for details please refer https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/datatypes/PostMetricDataDetails
        ARR_METRIC_DATA := JSON_ARRAY_T();

        -- PostMetrics api has soft limit of 50 unique metric stream per call, hence we cap it at 50. 
        -- For Production usecase where every metric data point is important, we can use chunking
        FOR METRIC_ROW IN (SELECT * FROM SHOPPING_ORDER_METRICS_TABLE 
                            ORDER BY CREATED_DATE DESC FETCH FIRST BATCH_SIZE_FOR_EACH_POST ROWS ONLY) LOOP
                            
            --DBMS_OUTPUT.PUT_LINE('inside for loop ' || METRIC_ROW.STATUS );

            METRIC_DATA_DETAILS := GET_METRIC_DATA_DETAILS_JSON_OBJ(
                                METRIC_ROW.STATUS,
                                OCI_METADATA_JSON_OBJ.GET_STRING('COMPARTMENT_OCID'), 
                                OCI_METADATA_JSON_OBJ.GET_STRING('DATABASE_NAME'), 
                                METRIC_ROW.COUNT, 
                                TO_CHAR(METRIC_ROW.CREATED_DATE, 'yyyy-mm-dd"T"hh24:mi:ss.ff3"Z"'));
            --DBMS_OUTPUT.PUT_LINE('METRIC_DATA_DETAILS '|| METRIC_DATA_DETAILS.to_clob);
            ARR_METRIC_DATA.APPEND(METRIC_DATA_DETAILS);

        END LOOP;
        DBMS_OUTPUT.PUT_LINE('done with for loop ');
        OCI_POST_METRICS_BODY_JSON_OBJ := JSON_OBJECT_T();
        OCI_POST_METRICS_BODY_JSON_OBJ.PUT('metricData', ARR_METRIC_DATA);

        RETURN OCI_POST_METRICS_BODY_JSON_OBJ;
    END;
    /

   ```
   
   4. Next we need PL/SQL code to actually publish these converted metrics to *Oracle Cloud Monitoring Service* using PostMetricsData API.
      We achieve the same with PL/SQL function named `POST_METRICS_DATA_TO_OCI` and stored procedure `PUBLISH_BUFFERED_METRICS_TO_OCI`.
   
   ```plsql

    CREATE OR REPLACE FUNCTION POST_METRICS_DATA_TO_OCI(OCI_POST_METRICS_BODY_JSON_OBJ JSON_OBJECT_T, ADB_REGION VARCHAR2) 
    RETURN NUMBER 
    IS
        RETRY_COUNT                    INTEGER := 0;
        MAX_RETRIES                    INTEGER := 3;
        RESP                           DBMS_CLOUD_TYPES.RESP;
        EXCEPTION_POSTING_METRICS      EXCEPTION;
        SLEEP_IN_SECONDS               INTEGER := 5;
    BEGIN
        FOR RETRY_COUNT in 1..MAX_RETRIES  LOOP
                -- invoking REST endpoint for OCI Monitoring API
                -- for details please refer https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData
            RESP := DBMS_CLOUD.SEND_REQUEST(CREDENTIAL_NAME => 'OCI$RESOURCE_PRINCIPAL', 
                                            URI => 'https://telemetry-ingestion.'|| ADB_REGION|| '.oraclecloud.com/20180401/metrics', 
                                            METHOD =>DBMS_CLOUD.METHOD_POST, 
                                            BODY => UTL_RAW.CAST_TO_RAW(OCI_POST_METRICS_BODY_JSON_OBJ.TO_STRING));

            IF DBMS_CLOUD.GET_RESPONSE_STATUS_CODE(RESP) = 200 THEN    -- when it is 200 from OCI Metrics API, all good
                DBMS_OUTPUT.PUT_LINE('POSTED METRICS SUCCESSFULLY TO OCI MONIOTRING');
                RETURN 200;
            ELSIF DBMS_CLOUD.GET_RESPONSE_STATUS_CODE(RESP) = 429 THEN -- 429 is caused by throttling
                IF RETRY_COUNT < MAX_RETRIES THEN
                    -- increase sleep time for each retry, doing exponential backoff
                    DBMS_SESSION.SLEEP(POWER(SLEEP_IN_SECONDS, RETRY_COUNT+1));
                    DBMS_OUTPUT.PUT_LINE('RETRYING THE POSTMETRICS API CALL');
                ELSE
                    DBMS_OUTPUT.PUT_LINE('ABANDONING POSTMETRICS CALLS, AFTER 3 RETRIES, CAUSED BY THROTTLING, WILL BERETRIED IN NEXT SCHEDULED RUN');
                    RETURN 429;
                END IF;
            ELSE -- for any other http status code....1. log error, 2. raise exception and then quit posting metrics, as it is most probably a persistent error 
                    DBMS_OUTPUT.PUT_LINE('IRRECOVERABLE ERROR HAPPENED WHEN POSTING METRICS TO OCI MONITORING, PLEASE SEE CONSOLE FOR ERRORS');
                    -- Response Body in TEXT format
                    DBMS_OUTPUT.put_line('Body: ' || '------------' || CHR(10) || DBMS_CLOUD.get_response_text(resp) || CHR(10));
                    -- Response Headers in JSON format
                    DBMS_OUTPUT.put_line('Headers: ' || CHR(10) || '------------' || CHR(10) || DBMS_CLOUD.get_response_headers(resp).to_clob || CHR(10));
                    -- Response Status Code
                    DBMS_OUTPUT.put_line('Status Code: ' || CHR(10) || '------------' || CHR(10) || DBMS_CLOUD.get_response_status_code(resp));
                    RETURN 500;
            END IF;

        END LOOP;
    END;
    /

    CREATE OR REPLACE PROCEDURE PUBLISH_BUFFERED_METRICS_TO_OCI IS
        OCI_METADATA_JSON_RESULT       VARCHAR2(1000);
        OCI_METADATA_JSON_OBJ          JSON_OBJECT_T;
        ADB_REGION                     VARCHAR2(25);
        OCI_POST_METRICS_BODY_JSON_OBJ JSON_OBJECT_T;
        TYPE ID_ARRAY IS VARRAY(50) OF NUMBER;
        ARRAY                          ID_ARRAY;
        TOTAL_METRICS_STREAM_CNT       NUMBER;
        HTTP_CODE                      NUMBER;
        BATCH_SIZE_FOR_EACH_POST       NUMBER:=8; -- not more than 50! as per PostMetricsData API docs
    BEGIN
        -- get the meta-data for this ADB Instance like its OCI compartmentId, region and DBName etc; as JSON in oci_metadata_json_result
        SELECT CLOUD_IDENTITY INTO OCI_METADATA_JSON_RESULT FROM V$PDBS; 
        -- dbms_output.put_line(oci_metadata_json_result);

        -- convert the JSON string into PLSQL JSON native JSON datatype json_object_t variable named oci_metadata_json_result
        OCI_METADATA_JSON_OBJ := JSON_OBJECT_T.PARSE(OCI_METADATA_JSON_RESULT);

        
        WHILE(TRUE) LOOP
            SELECT COUNT(*) INTO TOTAL_METRICS_STREAM_CNT FROM SHOPPING_ORDER_METRICS_TABLE;
            IF(TOTAL_METRICS_STREAM_CNT < BATCH_SIZE_FOR_EACH_POST) THEN
                DBMS_OUTPUT.PUT_LINE('Only ' || TOTAL_METRICS_STREAM_CNT || ' metrics datapoints buffered(less than batch size' || BATCH_SIZE_FOR_EACH_POST || '), hence waiting for buffer to fill up');
                EXIT;
            END IF;   

            OCI_POST_METRICS_BODY_JSON_OBJ := PREPARE_JSON_OBJECT_FROM_METRIC_ROWS(OCI_METADATA_JSON_OBJ, BATCH_SIZE_FOR_EACH_POST);
            ADB_REGION := OCI_METADATA_JSON_OBJ.GET_STRING('REGION');

            HTTP_CODE := POST_METRICS_DATA_TO_OCI(OCI_POST_METRICS_BODY_JSON_OBJ, ADB_REGION);

            IF(HTTP_CODE = 200) THEN
                DBMS_OUTPUT.PUT_LINE('Deleting the published metrics');
                DELETE FROM SHOPPING_ORDER_METRICS_TABLE WHERE ID IN 
                                    (SELECT ID FROM SHOPPING_ORDER_METRICS_TABLE 
                                    ORDER BY CREATED_DATE DESC FETCH FIRST 50 ROWS ONLY);
            END IF;    
                            
            COMMIT;    

            -- PostMetricData API has TPS rate limit of 50, just for safety  
            -- Hence sleep for atleast seconds => (1/50) to avoid throttling
            -- DBMS_SESSION.SLEEP(seconds => (1/50));                                  
        END LOOP;
    END;
    /
   ```

   Let us start with understanding function `POST_METRICS_DATA_TO_OCI`, which actually invokes *PostMetricsData API*!
   As with every Oracle Cloud API, you need proper IAM authorization to invoke it. We pass the same as follows, with the named parameter `credential_name => 'OCI$RESOURCE_PRINCIPAL'`.
   The DB credential `OCI$RESOURCE_PRINCIPAL` is linked to dynamic group `adb_dg` we created earlier in step 2 and user `ECOMMERCE_USER` already has access to the same, from step 3.
   Hence by *chain of trust*, this PL/SQL script executed by `ECOMMERCE_USER` has authorization to post the custom metrics to *Oracle Cloud Monitoring Service*.
   ```plsql
    RESP := DBMS_CLOUD.SEND_REQUEST(CREDENTIAL_NAME => 'OCI$RESOURCE_PRINCIPAL', 
                                            URI => 'https://telemetry-ingestion.'|| ADB_REGION|| '.oraclecloud.com/20180401/metrics', 
                                            METHOD =>DBMS_CLOUD.METHOD_POST, 
                                            BODY => UTL_RAW.CAST_TO_RAW(OCI_POST_METRICS_BODY_JSON_OBJ.TO_STRING));
    ```
   `dbms_cloud.send_request` is an inbuilt PL/SQL stored procedure invoke any rest endpoint, preinstalled with every ADB. Here we are using it to invoke Oracle Cloud Monitoring Service REST API.
  
   Next we come to stored procedure `PUBLISH_BUFFERED_METRICS_TO_OCI`. It basically posts all buffered metrics to *Oracle Cloud Monitoring Service*, using all the functions and procedures we have discussed so far.
   To be performant it creates batches of size `BATCH_SIZE_FOR_EACH_POST` of metric data-points for each *PostMetricsData API* invocation.


6. Schedule and run scripts from step 4 & 5.
   1. We need to run the script from step 4 to populate the data in `SHOPPING_ORDER` table. Script will run approximately for 15 minutes on ATP with 1 OCPU and 1TB storage.
      
   ```plsql
   -- we schedule the data feed to run immedietely, asychronously and only once!
   BEGIN
        DBMS_SCHEDULER.CREATE_JOB(
                                JOB_NAME => 'POPULATE_DATA_FEED_JOB', 
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
   2. Only thing remaining is periodic execution of PL/SQL script from Step 5: computation and publishing to *Oracle Cloud Monitoring Service*.</br>
      We do it as follows with PL/SQL built-in stored procedure `DBMS_SCHEDULER.CREATE_JOB`. 
      It creates Oracle DB `SCHEDULED_JOB` lasting for 20 minutes(1200 seconds). And it does custom metrics computation and publishes it every minute.
      For production use-case configure it as per your needs.
   
   ```plsql
    BEGIN
        DBMS_SCHEDULER.CREATE_JOB(
                                JOB_NAME => 'POST_METRICS_TO_OCI_JOB', 
                                JOB_TYPE   => 'PLSQL_BLOCK',
                                JOB_ACTION => 'BEGIN 
                                                ECOMMERCE_USER.COMPUTE_AND_BUFFER_METRICS(); 
                                                ECOMMERCE_USER.PUBLISH_BUFFERED_METRICS_TO_OCI();
                                               END;',
                                START_DATE => SYSTIMESTAMP,                        -- start the first run immediately
                                REPEAT_INTERVAL => 'FREQ=SECONDLY;INTERVAL=60',    -- run this PLSQL_BLOCK every 60th second 
                                END_DATE => SYSTIMESTAMP + INTERVAL '1200' SECOND, -- this schedule is only active
                                AUTO_DROP => TRUE,                                 -- delete the schedule after 1200 seconds, effectively after its last run
                                ENABLED => TRUE,                                   -- enable this schedule as soon as it is created
                                COMMENTS => 'JOB TO POST DB METRICS TO OCI MONITORING SERVICE, RUNS EVERY 10TH SECOND');
    END;
    /   
   ``` 

8. Explore the published custom metrics on *Oracle Cloud Web Console*. 
   1. From the hamburger menu click *Metrics Explorer* as shown below.
   ![Go Metrics Explorer on OCI Console](https://github.com/mayur-oci/Custom-Metrics-For-ADB/blob/main/images/FindMetricsExplorer.png?raw=true)
   2. Choose from the *Metrics Explorer* namespace as `custom_metrics_from_adb`, resourceGroup as `ecommerece_adb` and metric name as `customer_orders_submitted` we have set for custom metrics. </br>As you can see, all the metadata and dimensions we have set for custom metrics are available for us.
      You can construct *MQL* queries to analyse these metrics, as per your needs and use-case. Next you might like to set up [Oracle Cloud Alarms](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Tasks/managingalarms.htm) on these metric stream, to alert your Ops team.
      This automates the Observability loop for your ADB metrics of your choice!
   ![](https://github.com/mayur-oci/Custom-Metrics-For-ADB/blob/main/images/CustomMetricExplore.png?raw=true "Explore Your Custom Metrics you have published")


## Conclusion
  We have learnt how to emit custom metrics from ADB to *Oracle Cloud Monitoring Service*, with simple PL/SQL scripts using OCI SDK for PL/SQL. Oracle database being the 'source of truth' for many of business workflows, this is a very powerful functionality.</br>
  Custom metrics are first class citizens of Oracle Cloud Monitoring Service, on par with native metrics. You can analyse them with the same powerful *Metrics Query Language* and setup *Alarms* on them to notify you whenever any event of interest or trouble happens.
  This gives us ultimate 'Single Pane of Glass' view for all your metrics, be it generated OCI Service or custom metrics generated by your applications and databases.

   


