/* user_rights table creation
 *
 * This table contains record defining user rights.      
 *
 * $Id$
 */

CREATE TABLE user_rights (
       id           SERIAL PRIMARY KEY,
       uref	    INT4 NOT NULL, /* ptr to users record */
       type	    INT4 NOT NULL, /* 1=server,2=zone,3=net,4=hostnamemask */
       ref	    INT4 NOT NULL, /* ptr to table specified by type field */
       mode	    TEXT, /* R,RW,RWS */     

       comment	    TEXT
);


