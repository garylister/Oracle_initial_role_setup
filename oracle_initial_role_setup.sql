--  CREATE NEW USER ROLES

-- comment this out for squirrel
SET SERVEROUTPUT ON;  

declare

-- create a collection to hold the list of users
type t_users is table of varchar2(20);

-- list of users/roles
v_users t_users := t_users ('SUPPORT','DEVELOPER','QA','QAFLYWAY');

v_standard varchar2(35) := 'select, update, insert, delete';

v_user_check number;
v_role_check number;
v_varchar_user varchar2(20);
v_env varchar2(4);
v_current_role varchar2(50);

-- get all the objects you need to grant privileges on
cursor cur_objects is
select owner, object_name, object_type from dba_objects where object_type in
('TABLE', 'VIEW', 'PROCEDURE', 'MATERIALIZED VIEW', 'PACKAGE', 'PACKAGE BODY')
-- get a list of database schemas the users need access to
and owner in ('SCHEMA1', 'SCHEMA2', 'SCHEMA3', 'SCHEMA4', 'SCHEMA5', 'SCHEMA6')
and object_name not like 'schema_version' 
order by owner, object_type, object_name;

v_cur_objects cur_objects%ROWTYPE;

-- this is used to get all the system privielges for the dev_developer and the test_ and prod_ qaflyway users (all the 'any')
-- it's more clear then using the system_PRIVILEGE_MAP table and the table is small enough that all the "like"s shouldn't hurt
cursor cur_sys_privs is 
select privilege from session_privs where (privilege like '%ANY INDEX' or privilege like '%ANY MATERIALIZED VIEW' or privilege like 
'%ANY PROCEDURE' or privilege like '%ANY SEQUENCE' or privilege like '%ANY SYNONYM' or privilege like '%ANY TABLE' or privilege 
like '%ANY TRIGGER' or privilege like '%ANY VIEW') and (privilege not like 'BACKUP%' and privilege not like 'COMMENT%' and 
privilege not like 'UNDER%' and privilege not like 'MERGE%' and privilege not like 'DEBUG%' and privilege not like 'FLASHBACK%')
order by privilege;


-- this also works  but it's really unclear what it's doing without a lot of comments
-- select name from system_PRIVILEGE_MAP where privilege in (-41,-42,-44,-45,-47,-48,-49,-50,-71,-72,-73,-81,-82,-91,
-- -92,-106,-107,-108,-109,-141,-142,-143,-144,-152,-153,-154,-173,-174,-175) ;


v_sys_privs varchar2(30);

-- get all of the schema_version tables for the developer roles so that devs can run flyway:info
cursor cur_schema_version is 
select owner, object_name from dba_objects where object_type = 'TABLE' and object_name like  'schema_version';

v_schema_version cur_schema_version%ROWTYPE;


begin

-- allows the environment to be set by a script
v_env := 'asdf';

-- if the databases have uniquely idetentifiable SIDs for each environment, you could
-- query the DB for the SID using sys_context('userenv','instance_name')
-- or 'select instance from v$thread' and use a Case or If statement to set v_env 


-- check the environment and verify it's a valid one
if upper(v_env) = 'DEV' or upper(v_env) = 'TEST' or upper(v_env) = 'PROD' then 

-- loop through the users
for i in 1..v_users.count loop

-- set the users as a varchar to make things easier
v_varchar_user := v_users(i);
DBMS_OUTPUT.PUT_LINE( v_varchar_user);

-- check if the user exists so we don't create a role that we don't need
select count into v_user_check from (select count(*) as count from dba_users where username = v_varchar_user);

if v_user_check = 1 then

-- concatenate the environment and the user to get the role name
v_current_role := upper(v_env)||'_'||v_varchar_user;
DBMS_OUTPUT.PUT_LINE(v_current_role);

-- check if the role name already exists
select count into v_role_check from (select count(*) as count from dba_roles where role = upper(v_current_role));

if v_role_check = 0 then
    -- we don't use a qaflyway role in dev
    if v_current_role = 'DEV_QAFLYWAY' then
    DBMS_OUTPUT.PUT_LINE( v_current_role|| ' not needed');
     v_current_role := '';   
     -- if the role doesn't exist create it
    else DBMS_OUTPUT.PUT_LINE( 'create role '||v_current_role);
     execute immediate 'create role '||v_current_role;
    end if;
else 
-- if the role does exist let us know
DBMS_OUTPUT.PUT_LINE( 'role '||v_current_role||' already exists');
end if;

end if;

-- if the role exists grant privileges to it.  this does not check if the privileges already exist, so that this can be run
-- at any time to update or fix all of the users privileges
         if v_current_role = 'DEV_DEVELOPER' or v_current_role = 'TEST_QAFLYWAY' or v_current_role = 'PROD_QAFLYWAY' then
            open cur_sys_privs;
            LOOP
            fetch cur_sys_privs into v_sys_privs;
            exit when cur_sys_privs%NOTFOUND;
            DBMS_OUTPUT.PUT_LINE('grant ' ||v_sys_privs|| ' to ' || v_current_role);
            execute immediate 'grant ' ||v_sys_privs|| ' to ' || v_current_role;
            end loop;
            close  cur_sys_privs;
            
            if v_current_role = 'DEV_DEVELOPER' then
            DBMS_OUTPUT.PUT_LINE('grant analyze any to ' || v_current_role ||';');
            execute immediate 'grant analyze any to ' || v_current_role ;
            DBMS_OUTPUT.PUT_LINE('GRANT SELECT_CATALOG_ROLE TO ' || v_current_role ||';');
            execute immediate 'GRANT SELECT_CATALOG_ROLE TO ' || v_current_role;
            DBMS_OUTPUT.PUT_LINE('GRANT ' || v_current_role ||' to '|| v_varchar_user||';');
            execute immediate 'GRANT ' || v_current_role ||' to '|| v_varchar_user;
            elsif v_current_role = 'TEST_QAFLYWAY' or v_current_role = 'PROD_QAFLYWAY' then
            DBMS_OUTPUT.PUT_LINE('GRANT ' || v_current_role ||' to '|| v_varchar_user||';');
            execute immediate 'GRANT ' || v_current_role ||' to '|| v_varchar_user;
            end if;
         
           elsif v_current_role like '%_SUPPORT' or v_current_role = 'DEV_QA' or v_current_role = 'TEST_QA'  then
                open cur_objects;
                LOOP
                fetch cur_objects into v_cur_objects;
                exit when cur_objects%NOTFOUND;
                if v_cur_objects.object_type = 'TABLE' then
                 DBMS_OUTPUT.PUT_LINE('grant ' || v_standard || ' on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role);  
                 execute immediate 'grant ' || v_standard || ' on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role;
               elsif v_cur_objects.object_type = 'PROCEDURE' or v_cur_objects.object_type like 'PACKAGE%' Then
               DBMS_OUTPUT.PUT_LINE('grant execute on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role);  
               execute immediate 'grant execute on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role;
                elsif v_cur_objects.object_type like '%VIEW' then 
                DBMS_OUTPUT.PUT_LINE('grant select on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role); 
                execute immediate 'grant select on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role;
               end if;
                end loop;
                close cur_objects;
                 
                 if v_current_role = 'PROD_SUPPORT' then
                 DBMS_OUTPUT.PUT_LINE('grant execute on rdsadmin.rdsadmin_util to ' || v_current_role ||';');
                 execute immediate 'grant execute on rdsadmin.rdsadmin_util to ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('GRANT SELECT_CATALOG_ROLE TO ' || v_current_role ||';');
                 execute immediate 'GRANT SELECT_CATALOG_ROLE TO ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('GRANT ' || v_current_role ||' to '|| v_varchar_user||';');
                 execute immediate 'GRANT ' || v_current_role ||' to '|| v_varchar_user;
                 elsif v_current_role = 'DEV_SUPPORT' or v_current_role = 'TEST_SUPPORT' then
                 DBMS_OUTPUT.PUT_LINE('grant analyze any to ' || v_current_role ||';');
                 execute immediate 'grant analyze any to ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('grant execute on rdsadmin.rdsadmin_util to ' || v_current_role ||';');
                 execute immediate 'grant execute on rdsadmin.rdsadmin_util to ' || v_current_role ;
                 DBMS_OUTPUT.PUT_LINE('GRANT SELECT_CATALOG_ROLE TO ' || v_current_role ||';');
                 execute immediate 'GRANT SELECT_CATALOG_ROLE TO ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('GRANT ' || v_current_role ||' to '|| v_varchar_user||';');
                 execute immediate 'GRANT ' || v_current_role ||' to '|| v_varchar_user;
                 elsif v_current_role = 'DEV_QA' or v_current_role = 'TEST_QA'  then
                 DBMS_OUTPUT.PUT_LINE('GRANT ' || v_current_role ||' to '|| v_varchar_user||';');
                 execute immediate 'GRANT ' || v_current_role ||' to '|| v_varchar_user;                 
                 end if;
         
          elsif v_current_role = 'PROD_QA' or v_current_role = 'TEST_DEVELOPER' or v_current_role = 'PROD_DEVELOPER'  then
                open cur_objects;
                LOOP
                fetch cur_objects into v_cur_objects;
                exit when cur_objects%NOTFOUND;
                if v_cur_objects.object_type = 'TABLE' or v_cur_objects.object_type like '%VIEW' then
                DBMS_OUTPUT.PUT_LINE('grant select on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role);
                execute immediate 'grant select on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role;
                elsif v_cur_objects.object_type = 'PROCEDURE' or v_cur_objects.object_type like 'PACKAGE%' Then
               DBMS_OUTPUT.PUT_LINE('grant execute on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role); 
                 execute immediate 'grant execute on ' ||v_cur_objects.owner||'.'||v_cur_objects.object_name || ' to ' || v_current_role;
               end if;
                end loop;
                close cur_objects;
                
                 if v_current_role like '%_DEVELOPER' then
                open cur_schema_version;
                LOOP
               fetch cur_schema_version into v_schema_version;
                exit when cur_schema_version%NOTFOUND;
                DBMS_OUTPUT.PUT_LINE('grant select on ' ||v_schema_version.owner||'."'||v_schema_version.object_name || '" to ' || v_current_role);
                  execute immediate 'grant select on ' ||v_schema_version.owner||'."'||v_schema_version.object_name || '" to ' || v_current_role;
                end loop;
                close  cur_schema_version;
                end if;
                
                if v_current_role = 'TEST_DEVELOPER' then 
                DBMS_OUTPUT.PUT_LINE('grant analyze any to ' || v_current_role ||';');
                  execute immediate 'grant analyze any to ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('grant execute on rdsadmin.rdsadmin_util to ' || v_current_role ||';');
                   execute immediate 'grant execute on rdsadmin.rdsadmin_util to ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('GRANT SELECT_CATALOG_ROLE TO ' || v_current_role ||';');
                   execute immediate 'GRANT SELECT_CATALOG_ROLE TO ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('GRANT ' || v_current_role ||' to '|| v_varchar_user||';');
                 execute immediate 'GRANT ' || v_current_role ||' to '|| v_varchar_user;                 
                elsif  v_current_role = 'PROD_DEVELOPER' then
                DBMS_OUTPUT.PUT_LINE('grant execute on rdsadmin.rdsadmin_util to ' || v_current_role ||';');
                  execute immediate 'grant execute on rdsadmin.rdsadmin_util to ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('GRANT SELECT_CATALOG_ROLE TO ' || v_current_role ||';');
                   execute immediate 'GRANT SELECT_CATALOG_ROLE TO ' || v_current_role;
                 DBMS_OUTPUT.PUT_LINE('GRANT ' || v_current_role ||' to '|| v_varchar_user||';');
                 execute immediate 'GRANT ' || v_current_role ||' to '|| v_varchar_user;
                elsif    v_current_role = 'PROD_QA' then 
                 DBMS_OUTPUT.PUT_LINE('GRANT ' || v_current_role ||' to '|| v_varchar_user||';');
                 execute immediate 'GRANT ' || v_current_role ||' to '|| v_varchar_user;                
                 end if;
              

         
         end if;

-- just to add a space between user outputs to make it easier to read
   DBMS_OUTPUT.PUT_LINE(' '); 
-- remove the current_role so a role doesn't get processed for privileges twice if a user doesn't exist 
     v_current_role := '';
   end loop; 
   
   else
   -- throw an exception if the environment variable is wrong
   raise_application_error( -20001, 'Invlaid environment '||v_env );

   end if;
   
   exception
   when others then dbms_output.put_line( sqlerrm );
   
end;
/
