/* users table creation
 *
 * This table contains user account information.
 *
 * $Id$
 */

CREATE TABLE users (
	id		SERIAL PRIMARY KEY,
	username	TEXT UNIQUE NOT NULL CHECK(username <> ''),
	password	TEXT,
	name		TEXT,
	superuser	BOOL DEFAULT false,
	server		INT4 DEFAULT -1,
	zone		INT4 DEFAULT -1,
	last		TIMESTAMP,	

	comment	    TEXT
) INHERITS(pokemon);

