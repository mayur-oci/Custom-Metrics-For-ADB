-- Execute this script as ADMIN user of Oracle ADB/ATP
-- ADMIN user is created for every ADB instance
DROP USER ECOMMERCE_USER CASCADE;
CREATE USER ECOMMERCE_USER IDENTIFIED BY "abcABC123!@#";
-- GRANT PDB_DBA, CDB_DBA TO ECOMMERCE_USER;
GRANT CREATE TABLE, ALTER ANY INDEX, CREATE PROCEDURE, CREATE JOB, SELECT ANY TABLE,
      EXECUTE ANY PROCEDURE, UPDATE ANY TABLE, CREATE SESSION,UNLIMITED TABLESPACE, CONNECT, RESOURCE  
  TO ECOMMERCE_USER; 
  

-- Enable Resource Principal to Access Oracle Cloud Infrastructure Resources for db-user ECOMMERCE_USER, we just created. 
-- For details, refer https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/resource-principal.html
EXEC DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(username => 'ECOMMERCE_USER');
-- The credential is owned by ADMIN user always. 
SELECT OWNER, CREDENTIAL_NAME FROM DBA_CREDENTIALS WHERE CREDENTIAL_NAME = 'OCI$RESOURCE_PRINCIPAL' AND OWNER = 'ADMIN';
-- To check if any other user, here ECOMMERCE_USER has access privilege, you have to check DBA_TAB_PRIVS view
SELECT * from DBA_TAB_PRIVS WHERE DBA_TAB_PRIVS.GRANTEE='ECOMMERCE_USER';

GRANT SELECT ON "SYS"."V_$PDBS" TO ECOMMERCE_USER;  
GRANT EXECUTE ON "C##CLOUD$SERVICE"."DBMS_CLOUD" to ECOMMERCE_USER;
GRANT EXECUTE on "SYS"."DBMS_LOCK" to ECOMMERCE_USER ;







