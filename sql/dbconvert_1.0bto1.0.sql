/* zones.sql */

ALTER TABLE zones ADD COLUMN flags INT;
ALTER TABLE zones ALTER COLUMN flags SET DEFAULT 0;
UPDATE zones SET flags=0;

ALTER TABLE zones ADD COLUMN forward CHAR(1);
ALTER TABLE zones ALTER COLUMN forward SET DEFAULT 'D';
UPDATE zones SET forward='D';

