/* ether_info table creation
 *
 * $Id:$
 */

/** This table contains Ethernet adapter manufacturer codes.  **/

CREATE TABLE ether_info (
       	ea		CHAR(6) PRIMARY KEY, /* manufacturer code 
					      (6 bytes in hex) */
       	info		TEXT /* manufacturer name & info */
);

