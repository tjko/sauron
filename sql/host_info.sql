/* host_info table creation
 *
 * This table contains additional (administrative) information about hosts.
 *
 * $Id$
 */

CREATE TABLE host_info (
	id	    SERIAL PRIMARY KEY,
        host	    INT4 NOT NULL, /* ptr to hosts table */
	huser	    CHAR(30),
	room	    CHAR(8),
        bldg	    CHAR(10),
	dept	    CHAR(20),
	comment     TEXT
) INHERITS(pokemon);


