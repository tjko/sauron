/* printer_entries table creation
 *
 * This table contains printer definition entries.
 *
 * $Id$
 */

CREATE TABLE printer_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=group,2=host,3=printer_class */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
	printer	    TEXT,
        comment     TEXT
);


