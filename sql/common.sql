/* common table(s) creation
 *
 * $Id$
 */


/* virtual table; generic fields for most of the tables */
CREATE TABLE pokemon ( 
       cdate	   TIMESTAMP DEFAULT CURRENT_TIMESTAMP, /* creation date */
       cuser	   CHAR(32) DEFAULT 'unknown',   /* creating user */
       mdate	   TIMESTAMP DEFAULT CURRENT_TIMESTAMP, /* modification date */
       muser	   CHAR(32) DEFAULT 'unknown', /* last changed by this user */
       expiration  TIMESTAMP
);

