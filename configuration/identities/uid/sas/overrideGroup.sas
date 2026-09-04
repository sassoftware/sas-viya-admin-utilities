/*
 * Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * Enter the id of the group to update along primary GID value.
 */
%let groupid='<< enter groupid >>';
%let gid=<< enter primary gid value >>;

proc sql;
  connect using pg_db;
  
  execute (UPDATE identities.extended_attributes 
               SET identity_gid=&gid 
               WHERE identity_id=&groupid and identity_type_cd=1) by pg_db;

  disconnect from pg_db;  
run;
quit;