/* user_rights table creation
 *
 * $Id$
 */

/** This table contains record defining user rights.  **/

CREATE TABLE user_rights (
	id	SERIAL PRIMARY KEY, /* unique ID */
	type	INT NOT NULL, /* type:
				   1=user_group
				   2=users */
	ref	INT NOT NULL, /* ptr to users table specified by type
				-->user_groups.id
				-->users.id */
	rtype	INT NOT NULL, /* type:
				1=server,
				2=zone,
				3=net,
				4=hostnamemask */
	rref	INT NOT NULL, /* ptr to table specified by type field */
	rule	CHAR(40) /* R,RW,RWS or regexp */     
);


