/* ether_info table creation
 *
 * This table contains Ethernet adapter manufacturer codes.      
 *
 * $Id$
 */

CREATE TABLE ether_info (
       	ea		CHAR(6) PRIMARY KEY,
       	info		TEXT
);

