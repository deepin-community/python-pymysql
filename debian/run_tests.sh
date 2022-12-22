#!/bin/sh
#
# test_mysql.sh - runs libdbi test suite for mysql driver using a temporary
# mysql server environment that doesn't distrubs any running MySQL server.
#
# Copyright (C) 2010 Clint Byrum <clint@ubuntu.com>
# Copyright (C) 2010 Thomas Goirand <zigo@debian.org>
#
# This script is free software; you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the Free
# Software Foundation; either version 2.1 of the License, or (at your option)
# any later version.
#
# This script is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this library; if not, write to:
# The Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301 USA

set -e
set -x

###############################
### RUN THE MYSQLD INSTANCE ###
###############################
MYTEMP_DIR=`mktemp -d`
ME=`whoami`

MYSQL_VERSION=`/usr/sbin/mysqld --version 2>/dev/null | grep Ver | awk '{print $3}' | cut -d- -f1`
MYSQL_VERSION_MAJ=`echo $MYSQL_VERSION | cut -d. -f1`
MYSQL_VERSION_MID=`echo $MYSQL_VERSION | cut -d. -f2`
MYSQL_VERSION_MIN=`echo $MYSQL_VERSION | cut -d. -f3`

if [ "${MYSQL_VERSION_MAJ}" -le 5 ] && [ "${MYSQL_VERSION_MID}" -lt 7 ] ; then
	MYSQL_INSTALL_DB_OPT="--force --skip-name-resolve" 
else
	MYSQL_INSTALL_DB_OPT="--basedir=/usr"
fi

# --force is needed because buildd's can't resolve their own hostnames to ips
mysql_install_db --no-defaults --datadir=${MYTEMP_DIR} ${MYSQL_INSTALL_DB_OPT} --user=${ME}
/usr/sbin/mysqld --no-defaults --skip-grant-tables --user=${ME} --socket=${MYTEMP_DIR}/mysql.sock --datadir=${MYTEMP_DIR} --skip-networking &

# This sets the path of the MySQL socket for any libmysql-client users, which includes
# the ./tests/test_dbi client
export MYSQL_UNIX_PORT=${MYTEMP_DIR}/mysql.sock

echo -n pinging mysqld.
attempts=0
while ! /usr/bin/mysqladmin --socket=${MYTEMP_DIR}/mysql.sock ping ; do
	sleep 3
	attempts=$((attempts+1))
	if [ ${attempts} -gt 10 ] ; then
		echo "skipping test, mysql server could not be contacted after 30 seconds"
		exit 0
	fi
done

# Create the db
mysql --socket=${MYTEMP_DIR}/mysql.sock --execute="CREATE DATABASE test_pymysql;"
mysql --socket=${MYTEMP_DIR}/mysql.sock --execute="CREATE DATABASE test_pymysql2;"

#####################
### RUN THE TESTS ###
#####################
MULTI_STATEMENTS=$(python3 -c 'from pymysql.constants import CLIENT ; print(CLIENT.MULTI_STATEMENTS)')
# Launch the tests
echo "[
{\"unix_socket\": \"${MYTEMP_DIR}/mysql.sock\", \"user\": \"root\", \"passwd\": \"\", \"db\": \"test_pymysql\", \"use_unicode\": true, \"client_flag\": $MULTI_STATEMENTS},
{\"unix_socket\": \"${MYTEMP_DIR}/mysql.sock\", \"user\": \"root\", \"passwd\": \"\", \"db\": \"test_pymysql2\", \"client_flag\": $MULTI_STATEMENTS }
]" >pymysql/tests/databases.json

if PYTHONPATH=. PYTHON=$1 $1 -m pytest -v pymysql ; then
	SUCCESS=0
	echo "Yeah, ran unit tests..."
else
	SUCCESS=1
	echo "Nei when running unit tests"
fi

rm pymysql/tests/databases.json

###############################################
### SHUTDOWN MYSQL AND CLEAN ITS TMP FOLDER ###
###############################################
/usr/bin/mysqladmin --socket=${MYTEMP_DIR}/mysql.sock shutdown
rm -rf ${MYTEMP_DIR}

exit $SUCCESS
