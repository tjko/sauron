/* hinfo_templates table creation
 *
 * $Id$
 */

/** HINFO templates table contains list of default values
    for HINFO records. **/

CREATE TABLE hinfo_templates (
	id	SERIAL PRIMARY KEY, /* unique ID */
	hinfo	TEXT NOT NULL CHECK(hinfo <> '') UNIQUE, /* HINFO value */
	type    INT4 DEFAULT 0,  /* type:
					0=hardware, 
					1=software */
	pri     INT4 DEFAULT 100 /* priority (defines the order in which
  			    entries are displayed in user interfaces) */
);


