/* ds_entries table creation
 *
 */

/** This table contains DS record entries. **/

CREATE TABLE ds_entries (
    id          SERIAL PRIMARY KEY, /* unique ID */
    type        INT4 NOT NULL, /* type:
                    	2=subdomain (delegation) */
    ref         INT4 NOT NULL, /* ptr to table specefied by type field
                    	-->hosts.id */
    key_tag     INT4 NOT NULL CHECK (key_tag >= 0 AND key_tag <= 65535), /* 16bit number */
    algorithm   INT4 NOT NULL CHECK (algorithm >= 0 AND algorithm <= 255), /* algorithm:
                        1=RSAMD5
                        3=DSA
                        5=RSASHA1
                        6=DSA-NSEC3-SHA1
                        7=RSASHA1-NSEC3-SHA1
                        8=RSASHA256
                        10=RSASHA512
                        12=ECC-GOST
                        13=ECDSAP256SHA256
                        14=ECDSAP384SHA384
                        15=ED25519
                        16=ED448
              ref. https://www.ietf.org/archive/id/draft-hardaker-dnsop-rfc8624-bis-02.html*/
    digest_type INT4 NOT NULL CHECK (digest_type >= 0), /* digest_type:
			1=SHA-1
                        2=SHA-256
			3=GOST R 34.11-94
			4=SHA-384
	      ref. https://www.ietf.org/archive/id/draft-hardaker-dnsop-rfc8624-bis-02.html*/
    digest  BYTEA      NOT NULL, /* digest */
    comment     TEXT /* comment */
);

CREATE INDEX ds_entries_ref_index ON ds_entries (type,ref);

