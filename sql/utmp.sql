/* utmp table creation
 *
 * $Id$
 */

CREATE TABLE utmp ( 
	cookie		CHAR(32) PRIMARY KEY,
	uid		INT4,
	uname		TEXT,
	addr		CIDR,
	superuser	BOOL DEFAULT false,
	auth		BOOL DEFAULT false,
	mode		INT4,
	w		TEXT,
	serverid	INT4 DEFAULT -1,
	server		TEXT,
	zoneid		INT4 DEFAULT -1,
	zone		TEXT,
	login		INT4 DEFAULT 0,
	last		INT4 DEFAULT 0,
	searchopts	TEXT,
	searchdomain	TEXT,
	searchpattern	TEXT
);

