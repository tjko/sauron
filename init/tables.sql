/* Sauron table templates
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


/* table to store server specific data (server can have multiple zones
   linked to it) */
CREATE TABLE servers ( 
       id	   SERIAL PRIMARY KEY,
       name	   TEXT UNIQUE NOT NULL CHECK(name <> ''),

       zones_only  BOOL DEFAULT false,
       no_roots	   BOOL DEFAULT false,

	/* named.conf options...more to be added as needed... */
       directory      TEXT,
       named_ca	      TEXT,
       pzone_path     TEXT DEFAULT '',
       szone_path     TEXT DEFAULT 'NS2/', 

       hostname	      TEXT,  /* primary servername for sibling zone SOAs */
       hostmaster     TEXT,  /* hostmaster name for sibling zone SOAs
	                        unless overided in zone */

       comment	      TEXT
	
       /* allow_transfer (cird_entries) */
       /* dhcp */
) INHERITS(pokemon);


/* table to store zone specific data (zone usually have bunch of
   host table records linked to it) */
CREATE TABLE zones ( /* zone table; contains zones */
       id	   SERIAL,
       server	   INT4 NOT NULL,

       active	   BOOL DEFAULT true,
       dummy	   BOOL DEFAULT false,
       type	   CHAR(1) NOT NULL, /* (H)int, (M)aster, (S)lave, 
				        (F)orward, ... */
       reverse	   BOOL DEFAULT false, /* true for reverse (arpa) zones */
       noreverse   BOOL DEFAULT false, /* if true, zone not used in reverse
				          map generation */
       nnotify	   BOOL DEFAULT true,
       chknames    CHAR(1) DEFAULT 'W', /* (W)arn, (F)ail, (I)gnore */
       class	   CHAR(2) DEFAULT 'in',
       name	   TEXT NOT NULL CHECK (name <> ''),
       hostmaster  TEXT,
       serial	   CHAR(10) DEFAULT '1999123001',
       refresh	   INT4 DEFAULT 43200,
       retry	   INT4 DEFAULT 3600,
       expire	   INT4 DEFAULT 604800,
       minimum	   INT4 DEFAULT 86400,
       ttl	   INT4 DEFAULT -1,
       comment	   TEXT,

       reversenet  CIDR,
       parent	   INT4 DEFAULT -1,

       /* allow_update (cidr_entries) */
       /* masters (cidr_entries) */
       /* ns (ns_entries) */
       /* mx (mx_entries) */
       /* txt (txt_entries) */
       /* dhcp (dhcp_entries) */

       CONSTRAINT  zones_key PRIMARY KEY (name,server)
) INHERITS(pokemon);


/* subnet descriptions, linked to server record. Used mainly for generating
   subnet map for DHCP and access control/user friendliness in front-ends. */
CREATE TABLE nets (
       id	   SERIAL,
       server	   INT4 NOT NULL,

       name	   TEXT,
       net	   CIDR NOT NULL,
       subnet      BOOL DEFAULT true,
       rp_mbox	   TEXT DEFAULT '.',
       rp_txt	   TEXT DEFAULT '.',
       no_dhcp     BOOL DEFAULT false, 
       dhcp	   TEXT[],

       comment	   TEXT,

       CONSTRAINT  nets_key PRIMARY KEY (net,server)
) INHERITS(pokemon);


/* group descriptions, linked to server record. Hosts can "belong" to
   one group and get DHCP/printer/etc definitions from that group. */
CREATE TABLE groups (
       id	    SERIAL,
       server	    INT4 NOT NULL,

       name	    TEXT NOT NULL CHECK(name <> ''),
       dhcp	    TEXT[],
       printer	    TEXT[],

       comment	    TEXT,

       CONSTRAINT   groups_key  PRIMARY KEY (name,server)
) INHERITS(pokemon);


/* host descriptions, linked to a zone record. Records in this table
   can describe host,subdomain delegation,plain mx entry,alias (cname),
   printer, or glue records (for delegations). */
CREATE TABLE hosts (
       id	   SERIAL, 
       zone	   INT4 NOT NULL,
       type	   INT4 DEFAULT 0, /* 0=misc,1=host,2=subdomain (delegation),
				      3=mx entry, 4=alias, 5=printer,
  				      6=glue record */
       
       domain	   TEXT NOT NULL CHECK(domain <> ''),
       ttl	   INT4 DEFAULT -1,
       class	   CHAR(2) DEFAULT 'IN',
       
       grp	   INT4 DEFAULT -1,  /* ptr to group */
       alias	   INT4 DEFAULT -1,  /* ptr to another rr record */
       cname       BOOL, /* if true CNAME alias, otherwise A record alias */
       cname_txt   TEXT,
       hinfo_hw	   TEXT,
       hinfo_sw	   TEXT,
       wks	   INT4 DEFAULT -1, /* ptr to rr_wks table entry */
       mx	   INT4 DEFAULT -1, /* ptr to rr_mx table entry */
       rp_mbox	   TEXT DEFAULT '.',
       rp_txt	   TEXT DEFAULT '.',
       router      INT4 DEFAULT 0, /* router if > 0, also router priority
	                              (1 being highest priority) */
       prn         BOOL DEFAULT false,
		
       ether	   CHAR(12),
       info	   TEXT,
			       
       comment	   TEXT,

       CONSTRAINT  hosts_key PRIMARY KEY (domain,zone)
) INHERITS(pokemon);



/* global table to store printer classes (printcap stuff)
   these classess maybe referred to in PRINTER fields in other tables. */
CREATE TABLE printer_classes (
       id           SERIAL PRIMARY KEY,
       name	    TEXT UNIQUE NOT NULL CHECK(name <> ''),

       printer	    TEXT[],
       dentries     TEXT[],  

       comment	    TEXT
) INHERITS(pokemon);


CREATE TABLE host_info (
	id	    SERIAL PRIMARY KEY,
        host	    INT4 NOT NULL, /* ptr to hosts table */
	huser	    CHAR(30),
	room	    CHAR(8),
        bldg	    CHAR(10),
	dept	    CHAR(20),
	comment     TEXT
) INHERITS(pokemon);



/* addresses (A records) for hosts, linked to a host record. */
CREATE TABLE rr_a (
      id	   SERIAL PRIMARY KEY,
      host	   INT4 NOT NULL, /* ptr to hosts table id */

      ip	   CIDR,
      reverse	   BOOL DEFAULT true, /* generate reverse (PTR) record */
      forward      BOOL DEFAULT true, /* generate (A) record */
      comment	   TEXT
);


/* WKS entry templates, hosts may link to one entry
   in this table. Entries are zone specific (should be server specific?) */
CREATE TABLE rr_wks (
      id	   SERIAL PRIMARY KEY,
      server	   INT4 NOT NULL,
      
      wks	   TEXT[],
      comment	   TEXT
);


/* MX entry templates, hosts may link to one entry in this table.
   Entries are zone specific. */
CREATE TABLE rr_mx (
       id	   SERIAL PRIMARY KEY,
       zone	   INT4 NOT NULL,

       mx	   TEXT[],
       comment	   TEXT
);




CREATE TABLE cidr_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=server (allow_transfer)
				      2=zone (allow_update)
				      3=zone (masters) */
        ref	    INT4 NOT NULL, /* ptr to table speciefied by type field */
	ip	    CIDR,
	comment     TEXT
);

CREATE TABLE dhcp_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=server,2=zone,3=host,4=net,5=group */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
	dhcp	    TEXT,
        comment     TEXT
);

CREATE TABLE printer_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=group,2=host,3=printer_class */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
	printer	    TEXT,
        comment     TEXT
);


CREATE TABLE ns_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=zone,2=host */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
	ns	    TEXT,
        comment     TEXT
);

CREATE TABLE txt_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=zone,2=host */
        ref         INT4 NOT NULL ,/* ptr to table speciefied by type field */
	txt	    TEXT,
        comment     TEXT
);

CREATE TABLE mx_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=zone,2=host,3=rr_mx */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
        pri	    INT4 NOT NULL CHECK (pri >= 0),
	mx	    TEXT,
        comment     TEXT
);

CREATE TABLE wks_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=host,2=rr_wks */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
	proto	    CHAR(10), /* tcp,udp */
	services    TEXT,
        comment     TEXT
);


/* ///////////////////////////////////////////////////// */


CREATE TABLE users (
	id	    SERIAL PRIMARY KEY,
	username    TEXT UNIQUE NOT NULL CHECK(username <> ''),
	password    TEXT,
	name	    TEXT,
	superuser   BOOL DEFAULT false,

	comment	    TEXT
) INHERITS(pokemon);

CREATE TABLE user_rights (
       id           SERIAL PRIMARY KEY,
       uref	    INT4 NOT NULL, /* ptr to users record */
       type	    INT4 NOT NULL, /* 1=server,2=zone,3=net,4=hostnamemask */
       ref	    INT4 NOT NULL, /* ptr to table specified by type field */
       mode	    TEXT, /* R,RW,RWS */     

       comment	    TEXT
);


CREATE TABLE ether_info (
       	ea		CHAR(6) PRIMARY KEY,
       	info		TEXT
);

/* eof */
