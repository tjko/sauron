/* wks_entries table creation
 *
 * This table contains WKS record entries      
 *
 * $Id$
 */

CREATE TABLE wks_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=host,2=rr_wks */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
	proto	    CHAR(10), /* tcp,udp */
	services    TEXT,
        comment     TEXT
);
