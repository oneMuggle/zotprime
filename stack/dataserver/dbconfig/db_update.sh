#!/bin/sh
set -uex

MYSQL="mariadb -h mariadb -P 3306 -u root -p${MARIADB_ROOT_PASSWORD}"
echo "ALTER TABLE libraries ADD hasData TINYINT( 1 ) NOT NULL DEFAULT '0' AFTER version , ADD INDEX ( hasData )" | $MYSQL zotero_master
echo "UPDATE libraries SET hasData=1 WHERE version > 0 OR lastUpdated != '0000-00-00 00:00:00'" | $MYSQL zotero_master
echo "ALTER TABLE libraries DROP COLUMN lastUpdated, DROP COLUMN version" | $MYSQL zotero_master
# Extend users.password from char(40) to varchar(60) to accommodate bcrypt hashes.
# bcrypt ($2y$10$...(22 chars salt + 31 chars hash)) is exactly 60 chars.
# Existing MD5 (32 hex chars) also fits in varchar(60). No data loss.
echo "ALTER TABLE users MODIFY password varchar(60) NOT NULL COLLATE utf8_bin" | $MYSQL zotprime_www
