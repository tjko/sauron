/* hosts table creation
 *
 * host descriptions, linked to a zone record. Records in this table
 * can describe host,subdomain delegation,plain mx entry,alias (cname),
 * printer, or glue records (for delegations). 
 *
 * $Id$
 */

/** This table contains host entries for a zone. **/

CREATE TABLE hosts (
       id	   SERIAL,  /* unique ID */
       zone	   INT4 NOT NULL, /* ptr to a zone table record
					-->zones.id */
       type	   INT4 DEFAULT 0, /* host type: 
				      	0=misc,
					1=host,
					2=subdomain (delegation),
				      	3=mx entry, 
					4=alias (cname), 
					5=printer,
  				      	6=glue record, 
					7=alias (arec),
					8=srv entry
					*/
       
       domain	   TEXT NOT NULL CHECK(domain <> ''), /* host domain name */
       ttl	   INT4,          /* TTL for host records, default if NULL */
       class	   CHAR(2) DEFAULT 'IN', /* class (IN) */
       
       grp	   INT4 DEFAULT -1,  /* ptr to group
					-->groups.id */
       alias	   INT4 DEFAULT -1,  /* ptr to another host record
					(for CNAME alias) */
       cname_txt   TEXT,	     /* CNAME value for out-of-zone alias */
       hinfo_hw	   TEXT,	     /* HINFO hardware */
       hinfo_sw	   TEXT,	     /* HINFO software */
       loc	   TEXT,             /* LOC record value */
       wks	   INT4 DEFAULT -1,  /* ptr to wks_templates table entry
					-->wks_templates.id */
       mx	   INT4 DEFAULT -1,  /* ptr to mx_templates table entry
					-->mx_templates.id */
       rp_mbox	   TEXT DEFAULT '.', /* RP mbox */
       rp_txt	   TEXT DEFAULT '.', /* RP txt */
       router      INT4 DEFAULT 0, /* router if > 0, also router priority
	                              (1 being highest priority) */
       prn         BOOL DEFAULT false, /* true for virtual printer entries */
		
       ether	   CHAR(12),        /* Ethernet address (MAC) */
       ether_alias INT4 DEFAULT -1, /* ptr to another host record
					(for ETHER address) */
       info	   TEXT,       /* Host info (appears as TXT record) */
       location	   TEXT,       /* Host location info */
       dept	   TEXT,       /* Department name */
       huser	   TEXT,       /* User info */

       model       TEXT,       /* host model info */
       serial	   TEXT,       /* serial number */
       misc	   TEXT,       /* misc info */
			       
       comment	   TEXT,       /* comment */

       CONSTRAINT  hosts_key PRIMARY KEY (domain,zone)
) INHERITS(common_fields);

