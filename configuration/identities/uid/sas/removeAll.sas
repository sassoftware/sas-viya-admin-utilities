/*
 * Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * Removes all UID/GID values.
 *
 * WARNING: This program removes all UID/GID values for all users and groups 
 * in the Viya deployment.
 */

proc sql;
  connect using pg_db;
  
  execute (DELETE FROM identities.extended_attributes) by pg_db;

  disconnect from pg_db;  
run;
quit;