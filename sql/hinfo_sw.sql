/**************************************************************************
 * hinfo_sw.sql  -- default HINFO software template entries
 *
 * $Id$
 */

INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('MS-WINDOWS-98',1,1);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('MS-DOS',1,2);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('MS-WINDOWS-95',1,10);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('MS-WINDOWS-NT',1,10);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('MS-WINDOWS-2000',1,10);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('MS-WINDOWS-2000',1,10);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('MACOS',1,10);

INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('UNIX-LINUX',1,20);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('UNIX-OPENBSD',1,20);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('UNIX-SOLARIS',1,20);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('UNIX-HPUX',1,20);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('UNIX-IRIX',1,20);

INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('POSTSCRIPT',1,30);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('PCL',1,30);

INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('LINUX-TERMINAL',1,40);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('XTERMINAL',1,40);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('VMS',1,40);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('NETWARE',1,40);

INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('SWITCH',1,50);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('HUB',1,50);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('ROUTER',1,50);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('ROUTER-ATM',1,50);
INSERT INTO hinfo_templates (hinfo,type,pri) VALUES('IOS',1,50);

/* eof */
