/* ns_entries table creation
 *
 * This table contains NS resource record definitions.       
 *
 * $Id$
 */

CREATE TABLE ns_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=zone,2=host */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
	ns	    TEXT,
        comment     TEXT
);

