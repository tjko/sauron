/* common table(s) creation
 *
 * $Id$
 */


/** virtual table; generic fields for most of the tables **/

CREATE TABLE common_fields ( 
       cdate	   INT4, /* creation date */
       cuser	   CHAR(8) DEFAULT 'unknown',   /* creating user */
       mdate	   INT4, /* modification date */
       muser	   CHAR(8) DEFAULT 'unknown', /* last changed by this user */
       expiration  INT4  /* expiration date */
);


/** global settings table **/

CREATE TABLE settings (
	key	TEXT NOT NULL CHECK(key <> ''), /* name os setting tuple */
	value	TEXT, /* string value of setting */
	ivalue  INT4, /* interger value of setting */
	
	CONSTRAINT global_key PRIMARY KEY (key)
);
