SET SERVEROUTPUT ON;

DECLARE
    compartment_id                  VARCHAR2(100) := 'ocid1.compartment.oc1..aaaaaaaa2z4wup7a4enznwxi3mkk55cperdk3fcotagepjnan5utdb3tvakq' ;
    region                          VARCHAR2(25)  := 'us-ashburn-1' ;
    xyz                             VARCHAR2(1000);
    dd                              date;
    ts                              TIMESTAMP WITH TIME ZONE;
    oci_post_metrics_body_json      json_object_t;
    metric_data_arr                 json_array_t;
    metric_data_entry               json_object_t;
    metric_data_entry_metadata      json_object_t;
    metric_data_entry_dimension     json_object_t;
    metric_data_entry_data_pt_arr   json_array_t;
    metric_data_entry_data_pt_entry json_object_t;
    resp                            dbms_cloud_types.RESP;
    attempt                         INTEGER := 0;
    EXCEPTION_POSTING_METRICS       EXCEPTION;
    SLEEP_IN_SECONDS                INTEGER := 5;

BEGIN
    ts := SYSTIMESTAMP AT TIME ZONE 'UTC';
    DBMS_OUTPUT.put_line(TO_CHAR(ts));


    xyz := TO_CHAR(ts, 'YYYY-MM-DD') || 'T' || TO_CHAR(ts, 'HH24') || ':' || TO_CHAR(ts, 'MM:SS.FF') || 'Z';
    DBMS_OUTPUT.put_line(xyz);


    xyz := TO_CHAR(Sysdate, 'YYYY-MM-DD HH24:MM:SS') || 'Z';
    DBMS_OUTPUT.put_line(xyz);

    DBMS_OUTPUT.PUT_LINE('Date in RFC 3339' || TO_CHAR(
            SYSTIMESTAMP AT TIME ZONE 'UTC',
            'yyyy-mm-dd"T"hh24:mi:ss.ff3"Z"'
        ));

    metric_data_entry := json_object_t();
    metric_data_entry.put('namespace', 'testnamespace');
    metric_data_entry.put('resourceGroup', 'testresourcegroup');
    metric_data_entry.put('compartmentId', compartment_id);
    metric_data_entry.put('name', 'testName');
    --metric_data_entry.put('batchAtomicity', 'false');

    metric_data_entry_metadata := json_object_t();
    metric_data_entry_metadata.put('unit', 'rowsupdated');

    metric_data_entry.put('metadata', metric_data_entry_metadata);

    metric_data_entry_dimension := json_object_t();
    metric_data_entry_dimension.put('dbname', 'testDB');
    metric_data_entry_dimension.put('schemaname', 'testschema');
    metric_data_entry.put('dimensions', metric_data_entry_dimension);

    metric_data_entry_data_pt_arr := json_array_t();
    metric_data_entry_data_pt_entry := json_object_t();
    metric_data_entry_data_pt_entry.put('timestamp',
                                        TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC', 'yyyy-mm-dd"T"hh24:mi:ss.ff3"Z"'));
    metric_data_entry_data_pt_entry.put('value', 10);
    metric_data_entry_data_pt_entry.put('count', 1);
    metric_data_entry_data_pt_arr.append(metric_data_entry_data_pt_entry);

    metric_data_entry.put('datapoints', metric_data_entry_data_pt_arr);


    metric_data_arr := json_array_t();
    metric_data_arr.append(metric_data_entry);

    oci_post_metrics_body_json := json_object_t();
    oci_post_metrics_body_json.put('metricData', metric_data_arr);

    DBMS_OUTPUT.put_line(metric_data_arr.to_string);

    WHILE (3 < 4) LOOP
            resp := dbms_cloud.send_request(
                    credential_name => 'OCI$RESOURCE_PRINCIPAL ',
                    uri => 'https://telemetry-ingestion.' || region || '.oraclecloud.com/20180401/metrics',
                    method => dbms_cloud.METHOD_POST,
                    body => UTL_RAW.cast_to_raw(oci_post_metrics_body_json.to_string) );

            IF DBMS_CLOUD.get_response_status_code(resp) = 429 THEN
                attempt := attempt + 1;
                IF attempt <= 3 THEN
                    DBMS_LOCK.SLEEP (SLEEP_IN_SECONDS * attempt); -- increase sleep time for each retry, caused by throttling
                    DBMS_OUTPUT.put_line('retrying the postmetrics api call');
                ELSE
                    DBMS_OUTPUT.put_line('Abandoning postmetrics calls, after 3 retries, caused by throttling');
                    EXIT;
                END IF;
                
            ELSIF DBMS_CLOUD.get_response_status_code(resp) <> 200 THEN
                -- Response Body in TEXT format
                DBMS_OUTPUT.put_line('Body: ' || '------------' || CHR(10) || DBMS_CLOUD.get_response_text(resp) || CHR(10));
                -- Response Headers in JSON format
                DBMS_OUTPUT.put_line('Headers: ' || CHR(10) || '------------' || CHR(10) || DBMS_CLOUD.get_response_headers(resp).to_clob || CHR(10));
                -- Response Status Code
                DBMS_OUTPUT.put_line('Status Code: ' || CHR(10) || '------------' || CHR(10) || DBMS_CLOUD.get_response_status_code(resp));
                RAISE EXCEPTION_POSTING_METRICS;
                
            ELSE -- when it is 200 from OCI Metrics API, all good
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
