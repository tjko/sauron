/* sshfp_entries table creation
 *
 */

/** This table contains SSHFP record entries. **/

CREATE TABLE sshfp_entries (
    id          SERIAL PRIMARY KEY, /* unique ID */
    type        INT4 NOT NULL, /* type:
                    	1=host */
    ref         INT4 NOT NULL, /* ptr to table specefied by type field
                    	-->hosts.id */
    algorithm   INT4 NOT NULL CHECK (algorithm >= 0), /* algorithms:
	                0=reserved
			1=RSA
			2=DSA
			3=ECDSA
			4=Ed25519
			6=Ed448 */
    hashtype    INT4 NOT NULL CHECK (hashtype >= 0), /* type:
	              	0=reserved
			1=SHA-1
			2=SHA-256*/
    fingerprint TEXT NOT NULL, /* fingerprint */
    comment     TEXT /* comment */
);

CREATE INDEX sshfp_entries_ref_index ON sshfp_entries (type,ref);

