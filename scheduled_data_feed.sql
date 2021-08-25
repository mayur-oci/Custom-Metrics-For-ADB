
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
   DELETE SHOPPING_ORDER;
  --EXECUTE IMMEDIATE  'TRUCATE TABLE SHOPPING_ORDER';

  --EXECUTE IMMEDIATE 'ALTER TABLE SHOPPING_ORDER ENABLE ROW MOVEMENT';

  --DBMS_LOCK.SLEEP(120);

  -- insert data
  FOR counter IN 1..total_rows_in_shopping_order LOOP
           arr_status_random_index := TRUNC(dbms_random.value(low => 1, high => 9));
           customer_id_random := TRUNC(dbms_random.value(low => 1, high => 8000));
           INSERT INTO SHOPPING_ORDER(STATUS, CUSTOMER_ID)
                     VALUES(array(arr_status_random_index), customer_id_random);
           COMMIT;          
           --DBMS_LOCK.SLEEP(1);          
  END LOOP;
  --dbms_output.put_line('inserted data');

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
            --dbms_output.put_line('updating same data');
         
            --DBMS_LOCK.SLEEP(ROUND(dbms_random.value(low => 1, high => 2)));          
  END LOOP;

  EXECUTE IMMEDIATE 'ANALYZE TABLE SHOPPING_ORDER COMPUTE STATISTICS';

END;
/


begin
    dbms_scheduler.create_job 
    (  
      job_name      =>  CONCAT('populate_data_feed_',''),--,DBMS_RANDOM.STRING('A', 10)),  
      job_type      =>  'STORED_PROCEDURE',  
      job_action    =>  'ADMIN.populate_data_feed',  
      enabled       =>  TRUE,  
      auto_drop     =>  TRUE,  
      comments      =>  'one-time job');
  end;
/


SELECT job_name, job_class, operation, status FROM USER_SCHEDULER_JOB_LOG WHERE job_name LIKE2 'POPULATE%' and status = 'SUCCEEDED';
select * from all_scheduler_job_run_details WHERE owner='ADMIN' and job_name LIKE2 'POPULATE%' and status='SUCCEEDED' ORDER BY log_date DESC;
select owner as schema_name,
       job_name,
       job_style,
       case when job_type is null 
                 then 'PROGRAM'
            else job_type end as job_type,  
       case when job_type is null
                 then program_name
                 else job_action end as job_action,
       start_date,
       case when repeat_interval is null
            then schedule_name
            else repeat_interval end as schedule,
       last_start_date,
       next_run_date,
       state
from sys.all_scheduler_jobs
where owner = 'ADMIN'
order by owner,
         job_name;


  SELECT STATUS,count(*) FROM SHOPPING_ORDER GROUP BY STATUS;


