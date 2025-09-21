/* mx_entries table creation
 *
 * $Id:$
 */

/** This table contains MX record entries. **/

CREATE TABLE mx_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
					1=zone (not used anymore!),
					2=host,
					3=mx_templates */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field
					-->zones.id
					-->hosts.id
					-->mx_templates */
        pri	    INT4 NOT NULL CHECK (pri >= 0), /* MX priority */
	mx	    TEXT, /* MX domain (FQDN) */
        comment     TEXT
);

CREATE INDEX mx_entries_ref_index ON mx_entries (type,ref);

