/* user_rights table creation
 *
 * $Id$
 */

/** This table contains record defining user rights.  **/

CREATE TABLE user_rights (
       id           SERIAL PRIMARY KEY, /* unique ID */
       uref	    INT4 NOT NULL, /* ptr to users record
					-->users.id */
       type	    INT4 NOT NULL, /* type:
					1=server,
					2=zone,
					3=net,
					4=hostnamemask */
       ref	    INT4 NOT NULL, /* ptr to table specified by type field */
       mode	    TEXT, /* R,RW,RWS */     

       comment	    TEXT
);


