/* keys table creation
 *
 * $Id$
 */

/** This table contains TSIG/DNSSEC keys.  **/

CREATE TABLE keys (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
				      1=server */
        ref	    INT4 NOT NULL, /* ptr to table speciefied by type field
					-->servers.id
					-->acls.id  */

	name	    TEXT NOT NULL,  /* key name */
	keytype	    INT4 DEFAULT 0, /* key type (bitmap):
					0 = AUTHCONF
					1 = NOCONF (16384),
					2 = NOAUTH (32768),	
					3 = NOKEY */
	nametype    INT4 DEFAULT 0,  /* name type:
					0 = USER,
					1 = ZONE (256),
					2 = ENTITY (512) */		 

	protocol    INT4 NOT NULL, /* key validity for protocols:
 					0 = reserved,
					1 = TLS,
					2 = email,
					3 = dnssec,	
					4 = IPSEC,
					255 = All */
	algorithm   INT4 NOT NULL, /* algorithm:
					0 = reserved,
					1 = RSA/MD5 [RFC2437],
					2 = Diffie-Hellman [RFC2539],
					3 = DSA [RFC 2536],
					4 = reserved for ECC (elliptic curve),
					157 = HMAC MD5
					*/

	mode	    INT4 DEFAULT 0,  /* key autogeneration mode:
					0 = autogenerate key,
					1 = manually set key */   
	keysize	    INT4 DEFAULT -1, /* number of bits in the key */
	strength    INT4 DEFAULT 0,  /* reserved for key strength */	
	publickey   TEXT,	     /* public key (MIME64) */
	secretkey   TEXT,	     /* secret key (encrypted MIME74) */
	
	comment     TEXT,

	CONSTRAINT  keyname_key UNIQUE(name,ref,type)
) INHERITS(common_fields);
