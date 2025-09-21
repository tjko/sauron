/* lastlog table creation
 *
 * $Id:$
 */

/** lastlog table contains "lastlog" data of database users **/

CREATE TABLE lastlog (
	id		SERIAL PRIMARY KEY, /* unique ID */

	sid		INT NOT NULL, /* session ID */
	uid		INT NOT NULL, /* user ID */
	date	   	INT NOT NULL, /* date of record */
	state    	INT NOT NULL, /* record type: 
					  1=logged in
					  2=logged out 
					  3=idle timeout
					  4=reconnect  */
	ldate		INT DEFAULT -1, /* logout date */
	ip		INET,	        /* remote IP */
	host		TEXT		/* remote host */
);


