SET SERVEROUTPUT ON;

create table SHOPPING_ORDER
(
    ID                 INTEGER not null auto primary key,
    CREATED_DATE       TIMESTAMP(6),
    DETAILS            VARCHAR2(1000),
    LAST_UPDATED_DATE  TIMESTAMP(6),
    STATUS             VARCHAR2(30 char),
    TOTAL_CHARGES      FLOAT,
    CUSTOMER_ID        NUMBER(19)
)
/

DECLARE 
  arr_status_random_index INTEGER;
  customer_id_random INTEGER;
  type STATUS_ARRAY IS VARRAY(5) OF VARCHAR2(30); 
  status_array STATUS_ARRAY; 

BEGIN
  status_array := STATUS_ARRAY('ACCEPTED','PAYMENT_REJECTED', 'SHIPPED', 'ABORTED', 
                               'OUT_FOR_DELIVERY', 'ORDER_DROPPED_NO_INVENTORY', 
                               'PROCESSED', 'NOT_FULLFILLED');
  arr_status_random_index := dbms_random.value(1,8);
  
  
  INSERT INTO SHOPPING_ORDER(CREATED_DATE, DETAILS, LAST_UPDATED_DATE, STATUS, TOTAL_CHARGES, CUSTOMER_ID)
  VALUES()

END;
/










CREATE PROCEDURE POST_CUSTOM_METRICS_TO_OCI
    IS
    compartment_id             VARCHAR2(100) := 'ocid1.compartment.oc1..aaaaaaaa2z4wup7a4enznwxi3mkk55cperdk3fcotagepjnan5utdb3tvakq' ;
    region                     VARCHAR2(25)  := 'us-ashburn-1' ;
    oci_post_metrics_body_json json_object_t;
    arr_metric_data            json_array_t;
    metric_data_details        json_object_t;
    mdd_metadata               json_object_t;
    mdd_dimensions             json_object_t;
    arr_mdd_datapoint          json_array_t;
    mdd_datapoint              json_object_t;
    resp                       dbms_cloud_types.RESP;
    attempt                    INTEGER       := 0;
    EXCEPTION_POSTING_METRICS  EXCEPTION;
    SLEEP_IN_SECONDS           INTEGER := 5;

BEGIN

    -- prepare JSON body for postmetrics api..for details plz see https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData
    metric_data_details := json_object_t();
    metric_data_details.put('namespace', 'testnamespace');
    metric_data_details.put('resourceGroup', 'testresourcegroup');
    metric_data_details.put('compartmentId', compartment_id);
    metric_data_details.put('name', 'testName');
    --metric_data_entry.put('batchAtomicity', 'false');

    mdd_metadata := json_object_t();
    mdd_metadata.put('unit', 'rowsupdated');

    metric_data_details.put('metadata', mdd_metadata);

    mdd_dimensions := json_object_t();
    mdd_dimensions.put('dbname', 'testDB');
    mdd_dimensions.put('schemaname', 'testschema');
    metric_data_details.put('dimensions', mdd_dimensions);

    arr_mdd_datapoint := json_array_t();
    mdd_datapoint := json_object_t();
    mdd_datapoint.put('timestamp', TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC', 'yyyy-mm-dd"T"hh24:mi:ss.ff3"Z"')); --timestamp value RFC3339 compliant
    mdd_datapoint.put('value', 10);
    mdd_datapoint.put('count', 1);
    arr_mdd_datapoint.append(mdd_datapoint);

    metric_data_details.put('datapoints', arr_mdd_datapoint);


    arr_metric_data := json_array_t();
    arr_metric_data.append(metric_data_details);

    oci_post_metrics_body_json := json_object_t();
    oci_post_metrics_body_json.put('metricData', arr_metric_data);

    DBMS_OUTPUT.put_line(arr_metric_data.to_string);

    WHILE (TRUE)
        LOOP
            -- invoking REST endpoint for OCI Monitoring API
            resp := dbms_cloud.send_request(
                    credential_name => 'OCI$RESOURCE_PRINCIPAL ',
                    uri => 'https://telemetry-ingestion.' || region || '.oraclecloud.com/20180401/metrics',
                    method => dbms_cloud.METHOD_POST,
                    body => UTL_RAW.cast_to_raw(oci_post_metrics_body_json.to_string));

            IF DBMS_CLOUD.get_response_status_code(resp) = 429 THEN
                attempt := attempt + 1;
                IF attempt <= 3 THEN
                    DBMS_LOCK.SLEEP(SLEEP_IN_SECONDS * attempt); -- increase sleep time for each retry, caused by throttling
                    DBMS_OUTPUT.put_line('retrying the postmetrics api call');
                ELSE
                    DBMS_OUTPUT.put_line('Abandoning postmetrics calls, after 3 retries, caused by throttling');
                    EXIT;
                END IF;

            ELSIF DBMS_CLOUD.get_response_status_code(resp) <> 200 THEN
                -- Response Body in TEXT format
                DBMS_OUTPUT.put_line('Body: ' || '------------' || CHR(10) || DBMS_CLOUD.get_response_text(resp) ||
                                     CHR(10));
                -- Response Headers in JSON format
                DBMS_OUTPUT.put_line('Headers: ' || CHR(10) || '------------' || CHR(10) ||
                                     DBMS_CLOUD.get_response_headers(resp).to_clob || CHR(10));
                -- Response Status Code
                DBMS_OUTPUT.put_line('Status Code: ' || CHR(10) || '------------' || CHR(10) ||
                                     DBMS_CLOUD.get_response_status_code(resp));
                RAISE EXCEPTION_POSTING_METRICS;

            ELSE -- when it is 200 from OCI Metrics API, all good
                DBMS_OUTPUT.put_line('Posted metrics successfully to OCI moniotring');
                EXIT;

            END IF;
        END LOOP;


EXCEPTION
    WHEN EXCEPTION_POSTING_METRICS THEN
        dbms_output.put_line('Irrecoverable Error Happened when posting metrics to OCI Monitoring, please see console for errors');
    WHEN others THEN
        dbms_output.put_line('Error!');
END;
/
