SET SERVEROUTPUT ON;

TRUNCATE TABLE SHOPPING_ORDER;

alter table SHOPPING_ORDER enable row movement;

COMMIT;


DECLARE 
  arr_status_random_index INTEGER;
  customer_id_random INTEGER;
  type STATUS_ARRAY IS VARRAY(8) OF VARCHAR2(30); 
  array STATUS_ARRAY := STATUS_ARRAY('ACCEPTED','PAYMENT_REJECTED', 'SHIPPED', 'ABORTED', 
                               'OUT_FOR_DELIVERY', 'ORDER_DROPPED_NO_INVENTORY', 
                               'PROCESSED', 'NOT_FULLFILLED');
  total_rows_in_shopping_order INTEGER := 1000;                             
BEGIN     
  -- insert data
  FOR counter IN 1..total_rows_in_shopping_order LOOP
           arr_status_random_index := ROUND(dbms_random.value(low => 1, high => 8));
           customer_id_random := ROUND(dbms_random.value(low => 1, high => 8000));
           INSERT INTO SHOPPING_ORDER(STATUS, CUSTOMER_ID)
                     VALUES(array(arr_status_random_index), customer_id_random);
           COMMIT;          
           --DBMS_LOCK.SLEEP(1);          
  END LOOP;
  
  -- keep on updating the same data
  FOR counter IN 1..(total_rows_in_shopping_order*10) LOOP
           arr_status_random_index := ROUND(dbms_random.value(low => 1, high => 8));
           customer_id_random := ROUND(dbms_random.value(low => 1, high => 8000));
           
           INSERT INTO SHOPPING_ORDER(STATUS, CUSTOMER_ID)
                     VALUES(array(arr_status_random_index), customer_id_random);
                     
           UPDATE SHOPPING_ORDER SET STATUS=array(arr_status_random_index) WHERE rowid IN (
                 SELECT id_row FROM (
                      SELECT ROWID id_row FROM SHOPPING_ORDER ORDER BY dbms_random.value
                 ) RNDM WHERE rownum < ROUND(total_rows_in_shopping_order/20)
            );          
                     
           COMMIT;          
                     
           DBMS_LOCK.SLEEP(ROUND(dbms_random.value(low => 1, high => 5)));          
  END LOOP;
  
END;
/

--SELECT * FROM SHOPPING_ORDER PARTITION(OUT_FOR_DELIVERY);

--SELECT * FROM SHOPPING_ORDER WHERE status='NOT_FULLFILLED' and rownum < 10000;

exit;
