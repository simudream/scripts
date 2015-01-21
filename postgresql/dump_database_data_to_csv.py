import sys
import argparse
from subprocess import check_output

def retrieve_column_data(command, position):
    pg_database_data = check_output(command)
    #Remove the table headings, separators, result count and trailing lines
    pg_database_data = pg_database_data.split("\n")
    pg_database_data = pg_database_data[3:-3]

    databases = []

    #Remove unnecessary formatting and database information and get data from correct column
    for database_data in pg_database_data:
        database_data = database_data.split("|")
        if not database_data[position].isspace() and len(database_data[position]) > 1:
            databases.append(database_data[position].strip())

    #remove query result count and return list of databases
    return databases

#Set the argument parser and command line arguments
parser = argparse.ArgumentParser(description="Dump a postgresql database's tables to a set of csv files")
parser.add_argument('-d', dest='database', action='store', help='the name of the database to dump')
parser.add_argument('-l', dest='database_list', action='store_true', help='list the available databases')

args = parser.parse_args()

#Check and act on the arguments
if args.database == None or len(args.database) == 0:
    if args.database_list:
        #display a list of databases
        databases = retrieve_column_data(["psql","-l"],0)
        if 'template0' in databases: databases.remove('template0')
        if 'template1' in databases: databases.remove('template1')
        for database in databases:
            print(database)
            for table in retrieve_column_data(["psql",database,"-c",'\d'],1):
                print("\t- " + table)
        sys.exit()
    else:
        print("No valid options given (--help to list options)")
        sys.exit()
else:
    #retrieve a list of databases
    databases = retrieve_column_data(["psql","-l"],0)
    if args.database in databases:
        #retrieve a list of tables in the chosen database
        tables = retrieve_column_data(["psql",args.database,"-c",'\d'],1)
        for table in tables:
            check_output(["psql", args.database, "-c", "COPY " + table + " TO '/tmp/" + table + ".csv' CSV HEADER;"])
    sys.exit("hello")
