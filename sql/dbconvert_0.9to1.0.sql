/* SQL script to convert sauron database version 0.9 to 1.0 

   $Id$ 

   Usage: psql sauron -f <script> 
*/


/* servers.sql */

ALTER TABLE servers ADD COLUMN transfer_source INET;
ALTER TABLE servers ADD COLUMN version TEXT;
ALTER TABLE servers ADD COLUMN memstats_file TEXT;


ALTER TABLE servers ADD COLUMN dialup CHAR(1);
ALTER TABLE servers ALTER COLUMN dialup SET DEFAULT 'D';
UPDATE servers SET dialup='D';

ALTER TABLE servers ADD COLUMN fake_iquery CHAR(1);
ALTER TABLE servers ALTER COLUMN fake_iquery SET DEFAULT 'D';
UPDATE servers SET fake_iquery='D';

ALTER TABLE servers ADD COLUMN fetch_glue CHAR(1);
ALTER TABLE servers ALTER COLUMN fetch_glue SET DEFAULT 'D';
UPDATE servers SET fetch_glue='D';

ALTER TABLE servers ADD COLUMN has_old_clients CHAR(1);
ALTER TABLE servers ALTER COLUMN has_old_clients SET DEFAULT 'D';
UPDATE servers SET has_old_clients='D';

ALTER TABLE servers ADD COLUMN multiple_cnames CHAR(1);
ALTER TABLE servers ALTER COLUMN multiple_cnames SET DEFAULT 'D';
UPDATE servers SET multiple_cnames='D';

ALTER TABLE servers ADD COLUMN rfc2308_type1 CHAR(1);
ALTER TABLE servers ALTER COLUMN rfc2308_type1 SET DEFAULT 'D';
UPDATE servers SET rfc2308_type1='D';

ALTER TABLE servers ADD COLUMN use_id_pool CHAR(1);
ALTER TABLE servers ALTER COLUMN use_id_pool SET DEFAULT 'D';
UPDATE servers SET use_id_pool='D';

ALTER TABLE servers ADD COLUMN treat_cr_space CHAR(1);
ALTER TABLE servers ALTER COLUMN treat_cr_space SET DEFAULT 'D';
UPDATE servers SET treat_cr_space='D';

ALTER TABLE servers ADD COLUMN also_notify CHAR(1);
ALTER TABLE servers ALTER COLUMN also_notify SET DEFAULT 'D';
UPDATE servers SET also_notify='D';


ALTER TABLE servers ADD COLUMN forward CHAR(1);
ALTER TABLE servers ALTER COLUMN forward SET DEFAULT 'D';
UPDATE servers SET forward='D';


ALTER TABLE servers ADD COLUMN masterserver INT;
ALTER TABLE servers ALTER COLUMN masterserver SET DEFAULT -1;
UPDATE servers SET masterserver=-1;


ALTER TABLE servers ADD COLUMN df_port INT;
ALTER TABLE servers ALTER COLUMN df_port SET DEFAULT 519;
UPDATE servers SET df_port=519;

ALTER TABLE servers ADD COLUMN df_max_delay INT;
ALTER TABLE servers ALTER COLUMN df_max_delay SET DEFAULT 60;
UPDATE servers SET df_max_delay=60;

ALTER TABLE servers ADD COLUMN df_max_uupdates INT;
ALTER TABLE servers ALTER COLUMN df_max_uupdates SET DEFAULT 10;
UPDATE servers SET df_max_uupdates=10;

ALTER TABLE servers ADD COLUMN df_mclt INT;
ALTER TABLE servers ALTER COLUMN df_mclt SET DEFAULT 3600;
UPDATE servers SET df_mclt=3600;

ALTER TABLE servers ADD COLUMN df_split INT;
ALTER TABLE servers ALTER COLUMN df_split SET DEFAULT 128;
UPDATE servers SET df_split=128;

ALTER TABLE servers ADD COLUMN df_loadbalmax INT;
ALTER TABLE servers ALTER COLUMN df_loadbalmax SET DEFAULT 3;
UPDATE servers SET df_loadbalmax=3;


UPDATE settings SET value='1.0' WHERE key='dbversion';

/* eof */
