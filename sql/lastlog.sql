/* lastlog table creation
 *
 * $Id$
 */

/** lastlog table contains "lastlog" data of database users **/

CREATE TABLE lastlog (
	id		SERIAL PRIMARY KEY, /* unique ID */

	sid		INT NOT NULL, /* session ID */
	uid		INT NOT NULL, /* user ID */
	date	   	INT NOT NULL, /* date of record */
	type    	INT NOT NULL  /* record type: 
					  1=login
					  2=logout
				  	  3=autologout  */
);


