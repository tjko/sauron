/* txt_entries table creation
 *
 * $Id$
 */

/** This table contains TXT record entries and miscellaneous text entries. **/

CREATE TABLE txt_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL,  /* type:
					1=zone (not used anymore!),
					2=host,
					3=server,
					10=server (BIND logging entry),
					11=server (BIND custom option),
                                        12=zone (custom zone file entries) */
        ref         INT4 NOT NULL , /* ptr to table speciefied by type field
					-->zones.id
					-->hosts.id
					-->servers.id */
	txt	    TEXT,           /* value of TXT record */
        comment     TEXT            /* comments */
);

