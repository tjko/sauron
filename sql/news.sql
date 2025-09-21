/* news table creation
 *
 * $Id:$
 */

/** This table contains motd/news to be displayed when user logs in...  **/

CREATE TABLE news (
	id		SERIAL PRIMARY KEY, /* unique ID */

	server		INT DEFAULT -1, /* ptr to server or -1 for global
					   news messages */
       	info		TEXT NOT NULL /* news/motd message */
) INHERITS(common_fields) WITH OIDS;


