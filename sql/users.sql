/* users table creation
 *
 * This table contains user account information.
 *
 * $Id$
 */

CREATE TABLE users (
	id	    SERIAL PRIMARY KEY,
	username    TEXT UNIQUE NOT NULL CHECK(username <> ''),
	password    TEXT,
	name	    TEXT,
	superuser   BOOL DEFAULT false,

	comment	    TEXT
) INHERITS(pokemon);

