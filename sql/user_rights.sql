/* user_rights table creation
 *
 * $Id:$
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
				0=group (membership),
				1=server,
				2=zone,
				3=net,
				4=hostnamemask,
				5=IP mask,
				6=authorization level,
				7=host expiration limit (days),
	                        8=default for dept,
				9=templatemask,
				10=groupmask,
                                11=deletemask (hostname),
	                        12=reqhostfield,
	                        13=privilege flags (AREC,CNAME,MX,...),
				100=remit (asset management),
				101=asset management flags  */
	rref	INT NOT NULL, /* ptr to table specified by type field */
	rule	CHAR(80) /* R,RW,RWS or regexp */
);

CREATE INDEX user_rights_ref_index ON user_rights (type,ref);
