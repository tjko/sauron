/* hinfo_templates table creation
 *
 * HINFO templates table contains list of default values for HINFO records
 *
 * $Id$
 */

CREATE TABLE hinfo_templates (
	id	SERIAL PRIMARY KEY,
	hinfo	TEXT NOT NULL CHECK(hinfo <> '') UNIQUE,
	type    INT4 DEFAULT 0,  /* 0=hardware, 1=software */
	pri     INT4 DEFAULT 100
);


