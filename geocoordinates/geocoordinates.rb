require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'optparse'

site = 'http://earth-info.nga.mil/gns/html/namefiles.html'
resource_directory = "."
dbms_type = ""
format ="csv"
options = {}

available_formats = ["sql","csv","json"]
available_dbms = ["postgres","oracle","mysql","sqlserver"]
headers = ["Latitude","Longitude","Location","Country Code","Country Name"]

#TODO: handle http errors
def retrieve_remote_geocoordinate_resources(site)
  base_uri = site[0..site.rindex(/\//)]
  country_codes = []
  page = Nokogiri::HTML(open(site))

  #puts page.class   # => Nokogiri::HTML::Document
  links = page.css('table tr td a')
  links.each do |link|
    #Nokogiri::XML::Element method
    if link.key?("href")
      if link["href"].length > 7 and link["href"][0..7] == "cntyfile"
        if link["href"][0] != "#"
          link_string = link["href"].to_s
          country_codes << link_string[9..-5]
        end
      end
    end
  end

  return country_codes
end

def retrieve_local_geocoordinate_resources(resource_directory)
  directories = Dir.glob(resource_directory + '/[a-z][a-z]').select {|f| File.directory? f}
  (0..directories.length - 1).each do |index|
    directories[index] = directories[index][resource_directory.length + 1..-1]
  end
  return directories.sort
end

def retrieve_geocoordinate_resources(site, country_codes)
  country_codes.each do |country_code|
    `rm #{country_code + ".zip"}`
    `wget #{site[0..-15] + "cntyfile/#{country_code}.zip"}`
    `mkdir #{country_code}`
    `unzip #{country_code + ".zip"} -d #{country_code}`
    `rm #{country_code + ".zip"}`
    #remove the headers and write to a new file
    if File.exist?(country_code + '/' + country_code + '.txt')
      `tail -n +2 #{country_code}/#{country_code}.txt > #{country_code}/#{country_code}`
    elsif not File.exist?(country_code + '/' + country_code + '.txt')
      abort("No data for: " + country_code)
    end
  end
end

def retrieve_country_code_mappings(site)
  table_items = []
  country_code_mappings = {}
  page = Nokogiri::HTML(open(site))

  tds = page.css('table tr td')
  tds.each do |td|
    #Nokogiri::XML::Element method
    table_items << td.text
  end

  (0..table_items.length - 1).each do |index|
    country_code_mappings[table_items[index + 1]] = table_items[index]
  end

  return country_code_mappings
end

def generate_csv_format(resource_directories, site, headers, country_code_mappings)
  puts headers.join(",")

  resource_directories.each do |directory|
    if File.exist?(directory + '/' + directory)
      data_file = File.open(directory + '/' + directory,'r')

      #parse each file
      File.foreach(data_file) { |line|

        #chop off at any commas within the string (an unexpected formatting error in the raw data)
        line = line.gsub(",",";")
        components = line.split "\t"

        #add the necessary data to the csv file in the format
        #Latitude","Longitude","Location","Country Code","Country Name
        puts components[3].strip + "," + components[4].strip + "," + components[22].strip + "," + directory.upcase.strip + "," + country_code_mappings[directory.downcase].strip
      }
    end
  end
end

def generate_json_format(resource_directories, site, headers, country_code_mappings)
  #rather than waiting for pretty print to handle the whole array, which could take a long 
  #time, just print each country and add the json array characters
  puts "["
  resource_directories.each do |directory|
    if File.exist?(directory + '/' + directory)
      data_file = File.open(directory + '/' + directory,'r')

      country_data = {:countryCode => directory.upcase.strip,
                      :countryName => country_code_mappings[directory.downcase].strip,
                      :locations => []}
  
      #parse each file
      File.foreach(data_file) { |line|

        #chop off at any commas within the string (an unexpected formatting error in the raw data)
        line = line.gsub(",",";")
        location = {}
        components = line.chomp.split("\t")

        if components.length < headers.length
          puts "Skipped due to mismatch of items to headers:" + headers.join(",") + ' ' + line
        else
          #add the data to a hash
          #Latitude","Longitude","Location","Country Code","Country Name
          location[:name] = components[22].strip
          location[:latitude] = components[3].strip
          location[:longitude] = components[4].strip
          country_data[:locations] << location
        end
      }
      puts JSON.pretty_generate(country_data)
      #TODO: need to check for last file and not add comma after
      puts ","
    end
  end
  puts "]"
end

#TODO: generate code for multiple dbms using insert statements 
def write_table_properties(dbms_type)
  case dbms_type
  when "oracle"
  when "postgres"
    #btree indexes default
    puts "CREATE SEQUENCE countries_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1;\n
      ALTER SEQUENCE countries_id_seq OWNED BY countries.id;\n
      ALTER TABLE countries ALTER id SET DEFAULT NEXTVAL('countries_id_seq');\n
      CREATE SEQUENCE locations_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1;\n
      ALTER SEQUENCE locations_id_seq OWNED BY locations.id;\n
      ALTER TABLE locations ALTER id SET DEFAULT NEXTVAL('locations_id_seq');\n
      CREATE INDEX locations_name_idx ON locations (name);\n
      CREATE INDEX locations_country_idx ON locations (country_id);\n"
  when "sqlserver"
  when "mysql"
    #btree indexes default
    #alter columns to store unicode
    puts "ALTER TABLE countries CHANGE id id INTEGER AUTO_INCREMENT;\n
      ALTER TABLE countries MODIFY name VARCHAR(255) CHARACTER SET utf8;\n
      ALTER TABLE locations CHANGE id id INTEGER AUTO_INCREMENT;\n
      ALTER TABLE locations MODIFY name VARCHAR(255) CHARACTER SET utf8;\n
      ALTER TABLE locations ADD INDEX locations_name_idx (name);\n
      ALTER TABLE locations ADD INDEX locations_country_idx (country_id);\n"
  end
end

def write_table_schemas()
  puts "CREATE TABLE countries (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    code VARCHAR(2) NOT NULL UNIQUE
    );\n\n
    CREATE TABLE locations (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    latitude DECIMAL(8,6) NOT NULL CHECK (latitude >= -90 and latitude <= 90),
    longitude DECIMAL(9,6) NOT NULL CHECK (longitude >= -180 and longitude <= 180),
    country_id INTEGER REFERENCES countries(id)
    );
    \n\n"
end

#TODO: handle long country and location names
def write_table_data(resource_directories, site, headers, country_code_mappings)
  country_id = 1

  resource_directories.each do |directory|
    if File.exist?(directory + '/' + directory)
      data_file = File.open(directory + '/' + directory,'r')

      puts "INSERT INTO countries (name,code) VALUES ('" + country_code_mappings[directory.downcase].strip.gsub(/['’]/,"''") + "','" + directory.upcase.strip  + "');"

      if not File.zero?(data_file)
        line_count = %x{wc -l #{directory}/#{directory}}.split[0].to_i
        current_line = 0
        puts "INSERT INTO locations (name,latitude,longitude,country_id) VALUES "
        #parse each file
        File.foreach(data_file) { |line|

          #chop off at any commas within the string (an unexpected formatting error in the raw data)
          line = line.gsub(',',";")
          #escape any single quotes
          line = line.gsub(/['’]/,"''")

          components = line.split "\t"

          #add the necessary data to the csv file in the format
          #"name", latitude","longitude","country_id"
          print "('" + components[22].strip + "','" + components[3].strip + "','" + components[4].strip + "'," + country_id.to_s + ")"
          if current_line < line_count - 1
            puts ",\n"
          else
            puts ";\n\n" 
          end
          current_line += 1
        }
        end
      country_id += 1
    end
  end
end

def generate_sql_format(resource_directories, site, headers, dbms_type, country_code_mappings)
  write_table_schemas()
  write_table_properties(dbms_type)
  write_table_data(resource_directories, site, headers, country_code_mappings)
end

def create_data(format, resource_directories, dbms_type, site, headers, country_code_mappings)
  case format
  when "csv"
    generate_csv_format(resource_directories, site, headers, country_code_mappings)
  when "json"
    generate_json_format(resource_directories, site, headers, country_code_mappings)
  when "sql"
    generate_sql_format(resource_directories, site, headers, dbms_type, country_code_mappings)
  end
end

OptionParser.new do |opts|
  opts.banner = "Usage: geocoordinate_retriever_and_formatter.rb [options]"

  opts.on("-F", "--force", "Force the download of all of the latest geocoordinate resources") do |f|
    options[:force] = true
  end

  opts.on("-d", "--directory", "The directory where the geocoordinate resources are stored") do |d|
    options[:directory] = d
  end

  opts.on("-tDBMS", "--dbmstypeDBMS", "DBMS to produce SQL for [postgres, mysql, oracle, sqlserver] (requires -f sql)") do |t|
    options[:dbms_type] = t
  end

  opts.on("-lLOCATION", "--listLOCATION", "List country codes [remote, local, diff]") do |l|
    options[:list] = l
  end

  opts.on("-fFORMAT", "--formatFORMAT", "Save the geocoordinate resources in the format [csv, json, sql (requires -t <dbms>)]") do |f|
    options[:format] = f
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end

end.parse!

if options.has_key?(:list)

  case options[:list]
  when "local"
    puts retrieve_local_geocoordinate_resources(resource_directory).sort.join(" ")
  when "diff"
    puts (retrieve_remote_geocoordinate_resources(site) - retrieve_local_geocoordinate_resources(resource_directory)).sort.join(" ")
  when "remote"
    puts retrieve_remote_geocoordinate_resources(site).sort.join(" ")
  else
    puts "Option not available"
  end

else
  if options.has_key?(:directory)
    resource_directory = options[:directory]
  end

  if options.has_key?(:force)
    #download new/replace all existing local resources
    retrieve_geocoordinate_resources(site, retrieve_remote_geocoordinate_resources(site))
  else
    #just retrieve the resources not available locally
    retrieve_geocoordinate_resources(site, retrieve_remote_geocoordinate_resources(site) - retrieve_local_geocoordinate_resources(resource_directory).sort)
  end

  if options.has_key?(:format)
    format = options[:format].downcase
    if available_formats.include?(format)
      if options.has_key?(:dbms_type)
        dbms_type = options[:dbms_type].downcase
        if available_dbms.include?(options[:dbms_type])
          if not options[:format] == "sql"
            abort("Can only specify a DBMS type with SQL format(-f)")
          end
        else
          abort("DBMS unavailable")
        end
      else
        if format.eql? "sql"
          abort("Format unavailable without -t option")
        end
      end
    else
      abort("Format unavailable")
    end

    create_data(format, retrieve_local_geocoordinate_resources(resource_directory), dbms_type, site, headers, retrieve_country_code_mappings(site))
  else
    if options.has_key?(:dbmstype)
      abort("Can only specify a DBMS type with SQL format (-t)")
    end
  end

end
