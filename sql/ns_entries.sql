/* ns_entries table creation
 *
 * $Id$
 */

/** This table contains NS resource record definitions. **/

CREATE TABLE ns_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
					1=zone,
					2=host */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field
					-->zones.id
					-->hosts.id */
	ns	    TEXT, /* value of NS record (FQDN) */
        comment     TEXT
);

