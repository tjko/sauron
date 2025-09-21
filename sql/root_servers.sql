/* root_Servers table creation
 *
 * $Id:$
 */

/** This table contains root server definitions. **/

CREATE TABLE root_servers (
	id		SERIAL PRIMARY KEY, /* unique ID */
	server		INT4 NOT NULL, /* ptr to server table id
					  -->servers.id */

	ttl		INT4 DEFAULT 3600000,
	domain		TEXT NOT NULL,  /* domainname */
	type		TEXT NOT NULL,  /* A,NS,... */
	value		TEXT NOT NULL   /* value */
) WITH OIDS;
