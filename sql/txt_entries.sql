/* txt_entries table creation
 *
 * This table contains TXT record entries.
 *
 * $Id$
 */

CREATE TABLE txt_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=zone,2=host */
        ref         INT4 NOT NULL ,/* ptr to table speciefied by type field */
	txt	    TEXT,
        comment     TEXT
);

