/* tls_profiles table creation
 *
 * $Id:$
 */

/** This table contains named TLS profiles used for DNS Zone Transfer over
    TLS (XoT, RFC 9103).  Each profile is emitted as a top-level
    `tls "<name>" { ... };` statement in the generated named.conf and can be
    referenced by zones (allow-transfer / masters) and by the server TLS
    listener.  **/

CREATE TABLE tls_profiles (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL DEFAULT 1, /* type:
					      1=server */
	ref	    INT4 NOT NULL, /* ptr to table specified by type field
					-->servers.id */

	name	    TEXT NOT NULL,  /* profile name, used as `tls "<name>"` */
	cert_file   TEXT,           /* cert-file (PEM) */
	key_file    TEXT,           /* key-file (PEM) */
	ca_file     TEXT,           /* ca-file (peer certificate verification) */
	dhparam_file TEXT,          /* dhparam-file */
	protocols   TEXT,           /* allowed protocols, e.g. "TLSv1.2 TLSv1.3" */
	ciphers     TEXT,           /* OpenSSL cipher string */
	prefer_server_ciphers CHAR(1) DEFAULT 'D', /* D=default, Y=yes, N=no */
	session_tickets CHAR(1) DEFAULT 'D',       /* D=default, Y=yes, N=no */
	remote_hostname TEXT,       /* remote-hostname (outgoing peer auth) */

	comment     TEXT,

	CONSTRAINT  tls_profile_name_key UNIQUE(name,ref,type)
) INHERITS(common_fields);

CREATE INDEX tls_profiles_ref_index ON tls_profiles (type,ref);
