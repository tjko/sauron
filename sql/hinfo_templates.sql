/* hinfo_templates table creation
 *
 * HINFO templates table contains list of default values for HINFO records
 *
 * $Id$
 */

CREATE TABLE hinfo_templates (
	hinfo	TEXT NOT NULL CHECK(hinfo <> '') PRIMARY KEY,
	type    INT4 DEFAULT 0,  /* 0=hardware, 1=software */
	pri     INT4 DEFAULT 100
);


