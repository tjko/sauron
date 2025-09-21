/* srv_entries table creation
 *
 * $Id:$
 */

/** This table contains MX record entries. **/

CREATE TABLE srv_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
					1=host */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field
					-->hosts.id */
        pri	    INT4 NOT NULL CHECK (pri >= 0), /* priority */
	weight	    INT4 NOT NULL CHECK (weight >= 0), /* weight */
	port        INT4 NOT NULL CHECK (port >= 0), /* port */
	target	    TEXT NOT NULL DEFAULT '.', /* target */
        comment     TEXT /* comment */
) WITH OIDS;

CREATE INDEX srv_entries_ref_index ON srv_entries (type,ref);

