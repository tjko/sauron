/* tlsa_entries table creation
 *
 */

/** This table contains TLSA record entries. **/

CREATE TABLE tlsa_entries (
    id          SERIAL PRIMARY KEY, /* unique ID */
    type        INT4 NOT NULL, /* type:
                    	1=host */
    ref         INT4 NOT NULL, /* ptr to table specefied by type field
                    	-->hosts.id */
    usage       INT4 NOT NULL CHECK (usage >= 0), /* usage:
	                0=PKIX-TA
			1=PKIX-EE
			2=DANE-TA
			3=DANE-EE */
    selector    INT4 NOT NULL CHECK (selector >= 0), /* type:
	              	0=Full certificate
			1=SubjectPublicKeyInfo */ 
    matching_type INT4 NOT NULL CHECK (matching_type >= 0), /* type:
	              	0=No hash (direct compare)
			1=SHA‑256
                        2=SHA-512 */ 
    association_data  BYTEA      NOT NULL, /* certificate or its hash depends on selector and matching_type */
    comment     TEXT /* comment */
);

CREATE INDEX tlsa_entries_ref_index ON tlsa_entries (type,ref);

