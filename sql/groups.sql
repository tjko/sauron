/* groups table creation
 *
 * group descriptions, linked to server record. Hosts can "belong" to
 *  one group and get DHCP/printer/etc definitions from that group. 
 *
 * $Id$
 */

CREATE TABLE groups (
       id	    SERIAL,
       server	    INT4 NOT NULL,

       name	    TEXT NOT NULL CHECK(name <> ''),
       dhcp	    TEXT[],
       printer	    TEXT[],

       comment	    TEXT,

       CONSTRAINT   groups_key  PRIMARY KEY (name,server)
) INHERITS(pokemon);

