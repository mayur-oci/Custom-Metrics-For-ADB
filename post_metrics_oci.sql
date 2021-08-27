DECLARE
schema_nm VARCHAR(40);
db_name VARCHAR(40);
json_result VARCHAR2(1000);
tenant_ocid VARCHAR2(100);
db_metadata   json_object_t; 

BEGIN
 schema_nm := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
 db_name := SYS_CONTEXT('USERENV','INSTANCE_NAME');
 --dbms_output.put_line(schema_nm);
 --dbms_output.put_line(db_name);

 SELECT cloud_identity INTO json_result FROM v$pdbs;

 dbms_output.put_line(json_result);

 db_metadata := json_object_t.parse (json_result);

 dbms_output.put_line(db_metadata.get_string ('REGION'));
 dbms_output.put_line(db_metadata.get_string ('COMPARTMENT_OCID'));
  dbms_output.put_line(db_metadata.get_string ('DATABASE_NAME'));

END;
/

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
    metric_data_details.put('resourceGroup', 'adb_instances_group');
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
      dbms_output.put_line(indx || ': ' || array(indx));
      SELECT COUNT(*) INTO total_orders_by_status_cnt FROM SHOPPING_ORDER SO WHERE SO.STATUS=array(indx);
      
      metric_data_details := get_metric_data_details_json_obj(
                                array(indx),
                                oci_metadata_json_obj.get_string('COMPARTMENT_OCID'),
                                oci_metadata_json_obj.get_string('DATABASE_NAME'),
                                total_orders_by_status_cnt,
                                TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC', 'yyyy-mm-dd"T"hh24:mi:ss.ff3"Z"')
                            );

      arr_metric_data.append(metric_data_details);

    END LOOP;

    DBMS_OUTPUT.put_line(arr_metric_data.to_string);
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
    SELECT cloud_identity INTO oci_metadata_json_result FROM v$pdbs;
    dbms_output.put_line(oci_metadata_json_result);

    -- convert the JSON string into PLSQL JSON native JSON datatype json_object_t variable named oci_metadata_json_result
    oci_metadata_json_obj := json_object_t.parse(oci_metadata_json_result);
    oci_post_metrics_body_json_obj := compute_metric_and_prepare_json_object(oci_metadata_json_obj);
    
    adb_region := oci_metadata_json_obj.get_string('REGION');
    WHILE (TRUE)
        LOOP
            -- invoking REST endpoint for OCI Monitoring API
            -- for details please refer https://docs.oracle.com/en-us/iaas/api/#/en/monitoring/20180401/MetricData/PostMetricData
            resp := dbms_cloud.send_request(
                    credential_name => 'OCI$RESOURCE_PRINCIPAL ',
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
