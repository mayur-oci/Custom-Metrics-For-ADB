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
3. If you are going to use SQL Developer or Other desktop clients, then you also need to know about [how to connect to ADB using Wallet](https://docs.oracle.com/en/cloud/paas/autonomous-data-warehouse-cloud/cswgs/autonomous-connect-sql-developer.html#GUID-14217939-3E8F-4782-BFF2-021199A908FD).  
   To make things easier, In the tutorial we are going to use, [SQL Developer Web](https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/sql-developer-web.html#GUID-C32A78E5-4C5F-476F-86AB-AEEEA9CF2704), available right from OCI Console page for ATP.
4. ADMIN user access to your ADB/ATP instance.
5. Basic familiarity with Oracle Cloud Concepts like [Monitoring Service](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Concepts/monitoringoverview.htm), [PostMetrics api for publishing custom metrics](https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData) 
   & [Dynamic Groups and Resouce Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Concepts/overview.htm).

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
5. Read through the following PL/SQL scripts with the necessary stored procedures to populate data in ***SHOPPING_ORDER*** table. The script will keep on first adding 10000 rows into ***SHOPPING_ORDER*** table with random data and then it will update the same data.
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

6. Now let us dive deep into actual crux of this tutorial: script which computes the custom metrics and publishes it to Oracle Cloud Monitoring Service.
   ```plsql
    CREATE OR REPLACE FUNCTION get_metric_data_details_json_obj(
    in_order_status IN VARCHAR2,
    in_metric_cmpt_id IN VARCHAR2,
    in_adb_name IN VARCHAR2,
    in_metric_value IN NUMBER,
    in_ts_metric_collection IN VARCHAR2)
    RETURN json_object_t
    IS
    metric_data_details        json_object_t;
    mdd_metadata               json_object_t;
    mdd_dimensions             json_object_t;
    arr_mdd_datapoint          json_array_t;
    mdd_datapoint              json_object_t;
    BEGIN
    
        mdd_metadata := json_object_t();
        mdd_metadata.put('unit', 'total_row_count'); -- metric unit is arbitrary, as per choice of developer
    
        mdd_dimensions := json_object_t();
        mdd_dimensions.put('dbname', in_adb_name);
        mdd_dimensions.put('schema_name', SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
        mdd_dimensions.put('table_name', 'SHOPPING_ORDER');
        mdd_dimensions.put('order_status', in_order_status);
    
        mdd_datapoint := json_object_t();
        mdd_datapoint.put('timestamp', in_ts_metric_collection); --timestamp value RFC3339 compliant
        mdd_datapoint.put('value', in_metric_value);
        mdd_datapoint.put('count', 1);
        arr_mdd_datapoint := json_array_t();
        arr_mdd_datapoint.append(mdd_datapoint);
    
        metric_data_details := json_object_t();
    
        metric_data_details.put('datapoints', arr_mdd_datapoint);
        metric_data_details.put('metadata', mdd_metadata);
        metric_data_details.put('dimensions', mdd_dimensions);
    
        -- namespace, resourceGroup and name for the custom metric are arbitrary values, as per choice of developer
        metric_data_details.put('namespace', 'adb_custom_metrics_ns');
        metric_data_details.put('resourceGroup', 'adb_eco_group');
        metric_data_details.put('name', 'order_status');
        metric_data_details.put('compartmentId', in_metric_cmpt_id);
    
        RETURN metric_data_details;
    END;
    /
    
    
    
    CREATE OR REPLACE FUNCTION compute_metric_and_prepare_json_object(
    oci_metadata_json_obj      json_object_t)
    RETURN json_object_t
    IS
    total_orders_by_status_cnt  NUMBER := 0;
    
        oci_post_metrics_body_json_obj  json_object_t;
        type STATUS_ARRAY IS VARRAY(8) OF VARCHAR2(30); 
        array STATUS_ARRAY := STATUS_ARRAY('ACCEPTED','PAYMENT_REJECTED', 'SHIPPED', 'ABORTED', 
                                   'OUT_FOR_DELIVERY', 'ORDER_DROPPED_NO_INVENTORY', 
                                   'PROCESSED', 'NOT_FULLFILLED');
        arr_metric_data            json_array_t;
        metric_data_details        json_object_t;                
    BEGIN
    -- prepare JSON body for postmetrics api..
    -- for details please refer https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/datatypes/PostMetricDataDetails
    arr_metric_data := json_array_t();
    
        FOR indx in 1..array.count LOOP
          SELECT COUNT(*) INTO total_orders_by_status_cnt FROM SHOPPING_ORDER SO WHERE SO.STATUS=array(indx);
          
          metric_data_details := get_metric_data_details_json_obj(
                                    array(indx),
                                    'ocid1.compartment.oc1..aaaaaaaa2z4wup7a4enznwxi3mkk55cperdk3fcotagepjnan5utdb3tvakq', --oci_metadata_json_obj.get_string('COMPARTMENT_OCID'),
                                    oci_metadata_json_obj.get_string('DATABASE_NAME'),
                                    total_orders_by_status_cnt,
                                    TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC', 'yyyy-mm-dd"T"hh24:mi:ss.ff3"Z"')
                                );
    
          arr_metric_data.append(metric_data_details);
    
        END LOOP;
    
        -- DBMS_OUTPUT.put_line(arr_metric_data.to_string);
        oci_post_metrics_body_json_obj := json_object_t();
        oci_post_metrics_body_json_obj.put('metricData', arr_metric_data);
    
        RETURN oci_post_metrics_body_json_obj;
    END;
    /
    
    CREATE OR REPLACE PROCEDURE post_metrics_to_oci
    IS
    oci_metadata_json_result       VARCHAR2(1000);
    oci_metadata_json_obj          json_object_t;
    
        adb_region                     VARCHAR2(25);
        oci_post_metrics_body_json_obj json_object_t;
        resp                           dbms_cloud_types.RESP;
        attempt                        INTEGER                := 0;
        EXCEPTION_POSTING_METRICS      EXCEPTION;
        SLEEP_IN_SECONDS               INTEGER                := 5;
    
    BEGIN
    -- get the meta-data for this ADB Instance like its OCI compartmentId, region and DBName etc; as JSON in oci_metadata_json_result
    SELECT CLOUD_IDENTITY INTO OCI_METADATA_JSON_RESULT FROM V$PDBS;
    -- dbms_output.put_line(oci_metadata_json_result);
    
        -- convert the JSON string into PLSQL JSON native JSON datatype json_object_t variable named oci_metadata_json_result
        oci_metadata_json_obj := json_object_t.parse(oci_metadata_json_result);
        oci_post_metrics_body_json_obj := compute_metric_and_prepare_json_object(oci_metadata_json_obj);
        
        adb_region := oci_metadata_json_obj.get_string('REGION');
        WHILE (TRUE)
            LOOP
                -- invoking REST endpoint for OCI Monitoring API
                -- for details please refer https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData
                resp := dbms_cloud.send_request(
                        credential_name => 'OCI$RESOURCE_PRINCIPAL',
                        uri => 'https://telemetry-ingestion.' || adb_region || '.oraclecloud.com/20180401/metrics',
                        method => dbms_cloud.METHOD_POST,
                        body => UTL_RAW.cast_to_raw(oci_post_metrics_body_json_obj.to_string));
    
                IF DBMS_CLOUD.get_response_status_code(resp) = 200 THEN    -- when it is 200 from OCI Metrics API, all good
                    DBMS_OUTPUT.put_line('Posted metrics successfully to OCI moniotring');
                    EXIT;
                ELSIF DBMS_CLOUD.get_response_status_code(resp) = 429 THEN -- 429 is caused by throttling
                    attempt := attempt + 1;
                    IF attempt <= 3 THEN
                        DBMS_LOCK.SLEEP(SLEEP_IN_SECONDS * attempt);       -- increase sleep time for each retry, doing exponential backoff
                        DBMS_OUTPUT.put_line('retrying the postmetrics api call');
                    ELSE
                        DBMS_OUTPUT.put_line('Abandoning postmetrics calls, after 3 retries, caused by throttling');
                        EXIT;
                    END IF;
                ELSE -- for any other http status code....1. log error, 2. raise exception and then quit posting metrics, as it is most probably a persistent error 
                    -- Response Body in TEXT format
                    DBMS_OUTPUT.put_line('Body: ' || '------------' || CHR(10) || DBMS_CLOUD.get_response_text(resp) || CHR(10));
                    -- Response Headers in JSON format
                    DBMS_OUTPUT.put_line('Headers: ' || CHR(10) || '------------' || CHR(10) || DBMS_CLOUD.get_response_headers(resp).to_clob || CHR(10));
                    -- Response Status Code
                    DBMS_OUTPUT.put_line('Status Code: ' || CHR(10) || '------------' || CHR(10) || DBMS_CLOUD.get_response_status_code(resp));
                    RAISE EXCEPTION_POSTING_METRICS;
    
                END IF;
            END LOOP;
    
    
    EXCEPTION
    WHEN EXCEPTION_POSTING_METRICS THEN
    dbms_output.put_line('Irrecoverable Error Happened when posting metrics to OCI Monitoring, please see console for errors');
    WHEN others THEN
    dbms_output.put_line('Error!!!, please see console for errors');
    END;
    /
    
    
    BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
    job_name           =>  'POST_METRICS200',
    job_type           =>  'STORED_PROCEDURE',
    job_action         =>  'POST_METRICS_TO_OCI',
    start_date         =>   SYSTIMESTAMP,
    repeat_interval    =>  'FREQ=SECONDLY;INTERVAL=10', /* every 10th second */
    end_date           =>   SYSTIMESTAMP + INTERVAL '1500' SECOND,  /* in production prefer end_date instead or skip it alltogether */
    auto_drop          =>   TRUE,
    enabled            =>   TRUE,
    comments           =>  'job to post db metrics to oci monitoring service, runs every 10th second');
    END;
    /
       
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
  
   
   

