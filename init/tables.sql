/* Sauron table templates
 *
 * $Id$
 */


// virtual table; generic fields for most of the tables
CREATE TABLE pokemon ( 
       cdate	   TIMESTAMP DEFAULT CURRENT_TIMESTAMP, // creation date
       cuser	   CHAR(32) DEFAULT 'unknown',   // creating user
       mdate	   TIMESTAMP DEFAULT CURRENT_TIMESTAMP, // modification date
       muser	   CHAR(32) DEFAULT 'unknown',   // last changed by this user
       expiration  TIMESTAMP
);


// table to store server specific data (server can have multiple zones
// linked to it)
CREATE TABLE servers ( 
       id	   SERIAL PRIMARY KEY,
       name	   TEXT UNIQUE NOT NULL CHECK(name <> ''),

	// named.conf options...more to be added as needed...
       directory      TEXT,
       named_ca	      TEXT,
       allow_transfer CIDR[],
       pzone_path     TEXT DEFAULT '',
       szone_path     TEXT DEFAULT 'NS2/', 

       hostname	      TEXT,  // primary servername for sibling zone SOAs
       hostmaster     TEXT,  // hostmaster name for sibling zone SOAs
	                     // unless overided in zone

       dhcp 	      TEXT[],
       comment	      TEXT
) INHERITS(pokemon);


// table to store zone specific data (zone usually have bunch of
// host table records linked to it)
CREATE TABLE zones ( // zone table; contains zones
       id	   SERIAL,
       server	   INT4 NOT NULL,

       active	   BOOL DEFAULT true,
       type	   CHAR(1) NOT NULL, // (H)int, (M)aster, (S)lave, 
				     // (F)orward, ...
       reverse	   BOOL DEFAULT false,
       nnotify	   BOOL DEFAULT true,
       class	   CHAR(2) DEFAULT 'in',
       name	   TEXT NOT NULL CHECK (name <> ''),
       hostmaster  TEXT,
       serial	   CHAR(10) DEFAULT '1999123001',
       refresh	   INT4 DEFAULT 43200,
       retry	   INT4 DEFAULT 3600,
       expire	   INT4 DEFAULT 604800,
       minimum	   INT4 DEFAULT 86400,
       ttl	   INT4 DEFAULT -1,
       ns	   TEXT[],
       mx	   TEXT[],
       txt	   TEXT[],
       dhcp	   TEXT[], // entries to include for each host in zone
       comment	   TEXT,

       reverses	   INT4[],
       reversenet  CIDR,
       masters	   CIDR[], // used on slave zones
       parent	   INT4 DEFAULT -1,

       CONSTRAINT  zones_key PRIMARY KEY (name,server)
) INHERITS(pokemon);


// subnet descriptions, linked to server record. Used mainly for generating
// subnet map for DHCP and access control/user friendliness in front-ends. 
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


// group descriptions, linked to server record. Hosts can "belong" to
// one group and get DHCP/printer/etc definitions from that group.
CREATE TABLE groups (
       id	    SERIAL,
       server	    INT4 NOT NULL,

       name	    TEXT NOT NULL CHECK(name <> ''),
       dhcp	    TEXT[],
       printer	    TEXT[],

       comment	    TEXT,

       CONSTRAINT   groups_key  PRIMARY KEY (name,server)
) INHERITS(pokemon);


// host descriptions, linked to a zone record. Records in this table
// can describe host,subdomain delegation,plain mx entry,alias (cname),
// printer, or glue records (for delegations).
CREATE TABLE hosts (
       id	   SERIAL, 
       zone	   INT4 NOT NULL,
       type	   INT4 DEFAULT 0, // 0=misc,1=host,2=subdomain (delegation),
				   // 3=mx entry, 4=alias, 5=printer,
				   // 6=glue record 
       
       domain	   TEXT NOT NULL CHECK(domain <> ''),
       ttl	   INT4 DEFAULT -1,
       class	   CHAR(2) DEFAULT 'IN',
       
       // a	   CIDR,
       grp	   INT4 DEFAULT -1,  // ptr to group
       alias	   INT4 DEFAULT -1,  // ptr to another rr record
       cname       BOOL, // if true CNAME alias, otherwise A record alias
       cname_txt   TEXT,
       hinfo_hw	   TEXT,
       hinfo_sw	   TEXT,
       wks	   INT4 DEFAULT -1, // ptr to rr_wks table entry
       wks_txt	   TEXT[],
       mx	   INT4 DEFAULT -1, // ptr to rr_mx table entry
       mx_txt	   TEXT[],
       ns	   TEXT[],
       txt	   TEXT[],
       rp_mbox	   TEXT DEFAULT '.',
       rp_txt	   TEXT DEFAULT '.',
       router      INT4 DEFAULT 0, // router if > 0, also router priority
	                           // (1 being highest priority)
       prn         BOOL DEFAULT false,
		
       ether	   CHAR(12),
       info	   TEXT,
       dhcp	   TEXT[],
       printer	   TEXT[],
			       
       comment	   TEXT,

       CONSTRAINT  hosts_key PRIMARY KEY (domain,zone)
) INHERITS(pokemon);


// addresses (A records) for hosts, linked to a host record.
CREATE TABLE rr_a (
      id	   SERIAL PRIMARY KEY,
      host	   INT4 NOT NULL, // ptr to hosts table id

      ip	   CIDR,
      reverse	   BOOL DEFAULT true, // generate reverse (PTR) record
      forward      BOOL DEFAULT true, // generate (A) record 
      comment	   TEXT
);


// WKS entry templates, hosts may link to one entry
// in this table. Entries are zone specific (should be server specific?)
CREATE TABLE rr_wks (
      id	   SERIAL PRIMARY KEY,
      server	   INT4 NOT NULL,
      
      wks	   TEXT[],
      comment	   TEXT
);

// MX entry templates, hosts may link to one entry in this table.
// Entries are zone specific.
CREATE TABLE rr_mx (
       id	   SERIAL PRIMARY KEY,
       zone	   INT4 NOT NULL,

       mx	   TEXT[],
       comment	   TEXT
);



// global table to store printer classes (printcap stuff)
// these classess maybe referred to in PRINTER fields in other tables.
CREATE TABLE printer_classes (
       id           SERIAL PRIMARY KEY,
       name	    TEXT UNIQUE NOT NULL CHECK(name <> ''),

       printer	    TEXT[],
       dentries     TEXT[],  

       comment	    TEXT
) INHERITS(pokemon);



CREATE TABLE users (
	id	    SERIAL PRIMARY KEY,
	username    TEXT UNIQUE NOT NULL CHECK(username <> ''),
	password    TEXT,
	name	    TEXT,

	comment	    TEXT
) INHERITS(pokemon);


// eof
