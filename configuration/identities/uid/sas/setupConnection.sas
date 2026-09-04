/*
 * Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * Creates a libname statement used for establishing a connection to the database.
 *
 * Users must first obtain the proper password by issuing the following command
 * against the Kubernetes cluster:
 * 
 *    kubectl get secret sas-crunchy-data-postgres-dbmsowner-secret -o jsonpath="{.data.password}" | echo "$(base64 -d)"
 */
 
%let db_pwd=<< enter database password >>;
%let db_svr=sas-crunchy-data-postgres;
%let db_port=5432;
%let db_user=dbmsowner;
%let db_name=SharedServices;

libname pg_db
   postgres                  
   server = "&db_svr"
   port = &db_port
   user = &db_user
   password = &db_pwd
   database = &db_name;