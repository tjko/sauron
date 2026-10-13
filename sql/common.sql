/* common table(s) creation
 *
 * $Id:$
 */


/** virtual table; generic fields for most of the tables **/

CREATE TABLE common_fields ( 
       cdate	   INT4, /* creation date */
       cuser	   TEXT DEFAULT 'unknown',   /* creating user */
       mdate	   INT4, /* modification date */
       muser	   TEXT DEFAULT 'unknown', /* last changed by this user */
       expiration  INT4  /* expiration date */
);


/** virtual table; generic fields (with TIMESTAMP dates) for the
    approval workflow tables **/

CREATE TABLE pokemon (
       cdate      TIMESTAMP DEFAULT CURRENT_TIMESTAMP, /* creation date */
       cuser      TEXT DEFAULT 'unknown',              /* creating user */
       mdate      TIMESTAMP DEFAULT CURRENT_TIMESTAMP, /* modification date */
       muser      TEXT DEFAULT 'unknown',              /* last changed by this user */
       expiration TIMESTAMP                            /* expiration date */
);


/** global settings table **/

CREATE TABLE settings (
	setting	TEXT NOT NULL CHECK(setting <> ''), /* name of setting tuple */
	value	TEXT, /* string value of setting */
	ivalue  INT4, /* interger value of setting */
	
	CONSTRAINT global_key PRIMARY KEY (setting)
);
