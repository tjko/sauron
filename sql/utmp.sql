/* utmp table creation
 *
 * $Id$
 */

/** This table contains "utmp" data of currently logged in www-interface
    users. **/

CREATE TABLE utmp ( 
	cookie		CHAR(32) PRIMARY KEY, /* session id cookie (MD5) */
	uid		INT4, /* ptr to users table record
				 -->users.id */
	sid		INT4, /* session ID */
	uname		TEXT, /* username */
	addr		CIDR, /* user's IP address */
	superuser	BOOL DEFAULT false, /* superuser flag */
	auth		BOOL DEFAULT false, /* user authenticated flag */
	mode		INT4, /* current status of user */
	w		TEXT, /* last command user excecuted */
	serverid	INT4 DEFAULT -1, /* current server id */
	server		TEXT, /* current server name */
	zoneid		INT4 DEFAULT -1, /* current zone id */
	zone		TEXT, /* current zone name */
	login		INT4 DEFAULT 0, /* login time */
	last		INT4 DEFAULT 0, /* last activity time */
	searchopts	TEXT, /* current search options */
	searchdomain	TEXT, /* current search domain */
	searchpattern	TEXT  /* current search pattern */
);

