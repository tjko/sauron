/* users table creation
 *
 * $Id$
 */

/** This table contains (user interface) user account information. **/

CREATE TABLE users (
	id		SERIAL PRIMARY KEY, /* unique ID */
	gid		INT4 DEFAULT -1, /* ptr to user group 
					    -->usergroups.id */
	username	TEXT UNIQUE NOT NULL CHECK(username <> ''), /* login
									name */
	password	TEXT, /* encrypted password (MD5) */
	name		TEXT, /* long user name */
	superuser	BOOL DEFAULT false, /* superuser flag */
	server		INT4 DEFAULT -1, /* default server id */
	zone		INT4 DEFAULT -1, /* default zone id */
	last		INT4 DEFAULT 0,	/* last login time */
	last_pwd	INT4 DEFAULT 0, /* las password change time */
	search_opts	TEXT, /* default search options */

	comment	    TEXT
) INHERITS(pokemon);

