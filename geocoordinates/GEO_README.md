This script was built for retrieving worldwide location data comprised of location name, latitude, longitude, country name and country code. The data is limited to countries outside the US and has been made freely available. The intent of this project is to make this subset of the data more easily retrievable and convertable into alternate formats including JSON, CSV and SQL.

The script will download any differences (new country code zip files) from http://earth-info.nga.mil/gns/html/namefiles.html however will not update existing files with the latest data. If you need the latest data you can currently use the -f option to download all of the files. sha1 checksums are not currently set up.

The latitude and longitude data provided is accurate up to six decimal places. For a representation of what this means please see http://en.wikipedia.org/wiki/Decimal_degrees#Accuracy

===
Toponymic information is based on the Geographic Names Database, containing official standard names approved by the United States Board on Geographic Names and maintained by the National Geospatial-Intelligence Agency. More information is available at the Maps and Geodata link at www.nga.mil. The National Geospatial-Intelligence Agency name, initials, and seal are protected by 10 United States Code Section 425.


===Exporting to SQL

Define sql format with the -f option and your database type (postgres,oracle,mysql or sqlserver) with the -t option

===Examples (assumes you already have the dbms type installed)

====Produce JSON output
ruby geocoordinates.rb -f json > output.json

====Produce CSV output
ruby geocoordinates.rb -f csv > output.csv

====Produce SQL output and insert data to a PostGRES database

=====Create a database
sudo su postgres
psql
create database test;
\q
exit

=====Produce data and insert 
ruby geocoordinates.rb -f sql -t postgres > output.sql
sudo chown postgres:postgres output.sql
sudo su postgres
psql -d test -f output.sql

====Produce SQL output and insert data to a MySQL database
(You may need to adjust or add the my.cnf variables innodb_buffer_pool_size and max_allowed_packet if you get the message 'MySQL server has gone away')
=====Create a database
mysql
create database test;
exit

=====Produce data and insert
ruby geocoordinates.rb -f sql -t mysql > output.sql
mysql test < output.sql 

====List country code differences between what is stored locally and what is stored on the website
ruby geocoordinates.rb -l diff

====Force retrieve of the latest data
ruby geocoordinates.rb -f
