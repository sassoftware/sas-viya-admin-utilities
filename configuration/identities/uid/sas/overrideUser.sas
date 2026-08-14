/*
 * Enter the id of the user to update along with their UID and primary GID values.
 */
%let userid='<< enter userid >>';
%let uid=<< enter uid value >>;
%let gid=<< enter primary gid value >>;

proc sql;
  connect using pg_db;
  
  execute (UPDATE identities.extended_attributes 
               SET identity_uid=&uid, identity_gid=&gid 
               WHERE identity_id=&userid and identity_type_cd=0) by pg_db;

  disconnect from pg_db;  
run;
quit;