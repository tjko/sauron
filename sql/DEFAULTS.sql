/* adds necessary settings/defaults into settings table
 *
 * $Id:$
 */


/* database version (do not change unless you know what you're doing!) */

/* INSERT INTO settings (setting,value) VALUES('dbversion','1.3');*/
INSERT INTO settings (setting,value) VALUES('dbversion','1.5');


/* add BIND's built-in ACLs */
INSERT INTO acls (server,name) VALUES(-1,'any');
INSERT INTO acls (server,name) VALUES(-1,'none');
INSERT INTO acls (server,name) VALUES(-1,'localhost');
INSERT INTO acls (server,name) VALUES(-1,'localnets');




/* eof */
