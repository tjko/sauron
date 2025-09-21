/* history table creation
 *
 * $Id:$
 */

/** history table contains "log" data of modifications done to the
    databse **/

CREATE TABLE history (
	id		SERIAL PRIMARY KEY, /* unique ID */

	sid		INT NOT NULL, /* session ID */
	uid		INT NOT NULL, /* user ID */
	date	   	INT NOT NULL, /* date of record */
	type    	INT NOT NULL, /* record type:
					  1=hosts table modification,
					  2=zones
				  	  3=servers
					  4=nets
				      	  5=users */
	ref		INT,      /* optional reference */
	action		CHAR(25), /* operation performed */
	info		TEXT      /* extra info */
) WITH OIDS;

CREATE INDEX history_sid_index ON history(sid);
CREATE INDEX history_uid_index ON history(uid);
