/* root_Servers table creation
 *
 * contains root server definitions
 *
 * $Id$
 */

CREATE TABLE root_servers (
	id		SERIAL PRIMARY KEY,
	server		INT4 NOT NULL, /* ptr to server table id */

	ttl		INT4 DEFAULT 3600000,
	domain		TEXT NOT NULL,
	type		TEXT NOT NULL,  /* A,NS,... */
	value		TEXT NOT NULL   /* value */
);