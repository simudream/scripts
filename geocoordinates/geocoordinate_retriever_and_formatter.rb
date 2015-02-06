require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'optparse'

site = 'http://earth-info.nga.mil/gns/html/namefiles.html'
resource_filepath = "geocoords.csv"
output_filepath = "output"
directory = "."
dbms_type = ""

available_formats = ["sql","csv","json"]
available_dbms = ["postgres","oracle","mysql","sqlserver"]

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
  return directories
end

#TODO: handle command errors
#TODO: write checks to see if the commands exist
def retrieve_geocoordinate_resources(site, directory, force_download)
  resources = []
  if force_download
    resources = retrieve_remote_geocoordinate_resources(site)
  end

  resources.each do |resource|
      `rm #{resource + ".zip"}`
      `wget #{site[0..-15] + "cntyfile/#{resource}.zip"}`
      `mkdir #{resource}`
      `unzip #{resource + ".zip"} -d #{resource}`
      `rm #{resource + ".zip"}`
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

#get a list of directories and parse the contents, writing to a compiled geocoordinate file.
#TODO handle file errors
def generate_resource_file(output_filepath, resource_directories, country_code_mappings)
  File.open(output_filepath, "w+") do |resource_file|
    resource_file.puts "Latitude,Longitude,Location,Country Code,Country Name"

    resource_directories.each do |directory|
      #remove the headers
      if File.exist?(directory + '/' + directory + '.txt')
        system('tail -n +2 ' + directory + '/' + directory + '.txt' + ' > ' + directory + '/' + directory)
        data_file = File.open(directory + '/' + directory,'r')

        #write the new file
        File.foreach(data_file) { |line| 
          components = line.split "\t"

          #chop off at any commas within the string (an unexpected formatting error in the raw data)
          if not components[22].index(",") == nil
            components[22] = components[22][0..components[22].index(",") - 1]
          end

          #add the necessary data to the resource file
          resource_file.puts components[3].strip + "," + components[4].strip + "," + components[22].strip + "," + directory.upcase.strip + "," + country_code_mappings[directory.downcase].strip
        }
        File.delete(directory + '/' + directory)
      end
    end

  end
end

def generate_json(resource_file)
  #array for hashes of resource data to be converted to json
  resources = []
  
  #loop through the resource
  lines = IO.readlines(resource_file)
  #Check file not empty
  if lines.length > 0
    resource = {}
    headers = lines[0].chomp.split(",")
    (1..lines.length() - 1).each do |line_index|
      contents = lines[line_index].chomp.split(",")
      if contents.length() == headers.length()
        (0..headers.length() - 1).each do |index|
          resource[headers[index]] = contents[index]
        end
        resources << resource
      else
        puts "Skipped due to mismatch of items to headers:" + lines[line_index]
      end
    end
  else
    abort("Resource file empty")
  end

  return JSON.pretty_generate(resources)
end

def generate_sql_file(locations, countries, output_file, dbms_type)

  output_file.write("CREATE TABLE countries (
        id integer PRIMARY KEY,
        name varchar(255) NOT NULL UNIQUE,
        code varchar(2) NOT NULL UNIQUE
        );\n
        CREATE TABLE locations (
        id integer PRIMARY KEY,
        name varchar(255) NOT NULL UNIQUE,
        latitude DECIMAL(8,6) NOT NULL CHECK (latitude >= 0 and latitude <= 90),
        longitude DECIMAL(9,6) NOT NULL CHECK (longitude >= -180 and longitude <= 180),
        country_id integer references countries(id)
        );
        \n\n")

  case dbms_type
  when "oracle"
  when "postgres"
    output_file.write("ALTER TABLE countries ALTER id SET DEFAULT NEXTVAL('countries_id_seq');\n
       ALTER TABLE locations ALTER id SET DEFAULT NEXTVAL('locations_id_seq');\n
       CREATE SEQUENCE countries_id_seq
       START WITH 1
       INCREMENT BY 1
       NO MINVALUE
       NO MAXVALUE
       CACHE 1;\n
       ALTER SEQUENCE countries_id_seq OWNED BY countries.id;\n
       CREATE SEQUENCE locations_id_seq
       START WITH 1
       INCREMENT BY 1
       NO MINVALUE
       NO MAXVALUE
       CACHE 1;\n
       ALTER SEQUENCE locations_id_seq OWNED BY locations.id;\n")

  when "sqlserver"
  when "mysql"
  end

  output_file.write("INSERT INTO countries (name,code) VALUES \n")
  countries.each do |country|
    #escape any single quotes
    country[:name].gsub(/['’]/,"\'\'")
    output_file.write("('#{country[:name]}','#{country[:code]}')")
    if country != countries.last
      output_file.write(",\n")
    else
      output_file.write(";\n\n")
    end
  end

  output_file.write("INSERT INTO locations (name,latitude,longitude,country_id) VALUES \n")
  locations.each do |location|
    #escape any single quotes
    location[:name] = location[:name].gsub(/['’]/,"\'\'")
    output_file.write("('#{location[:name]}',#{location[:latitude]},#{location[:longitude]},#{location[:country_id]})")
    if location != locations.last
      output_file.write(",\n")
    else
      output_file.write(";\n\n")
    end
  end

end

#TODO: generate code for multiple dbms using insert statements 
def retrieve_table_data(resource_file)
  locations = []
  countries = []

  #loop through the resource
  lines = IO.readlines(resource_file)

  #Check file not empty
  if lines.length > 0
    headers = lines[0].chomp.split(",")
    (1..lines.length() - 1).each do |line_index|
      contents = lines[line_index].chomp.split(",")
      location_record = {:latitude => nil, :longitude => nil, :name => nil, :country_id => nil}
      country_record = {:name => nil, :code => nil}
      (0..headers.length() - 1).each do |index|
        case headers[index]
        when "Latitude"
          location_record[:latitude] = contents[index]
        when "Longitude"
          location_record[:longitude] = contents[index]
        when "Location"
          location_record[:name] = contents[index]
        when "Country Code"
          country_record[:code] = contents[index]
        when "Country Name"
          country_record[:name] = contents[index]
        end      
      end

      if not countries.include? country_record
        countries << country_record
      end

      location_record[:country_id] = countries.index(country_record)

      locations << location_record
    end

    return {:locations => locations, :countries => countries}
  else
    abort("Resource file empty")
  end
end

def create_data(format, resource_filepath, output_filepath,dbms_type)
  if File.exist?(resource_filepath)
    File.open(resource_filepath, "r") do |resource_file|
      file_valid = false
      begin
        file_valid = resource_file.readline.chomp.eql?("Latitude,Longitude,Location,Country Code,Country Name")
      rescue => e
        abort(e.message)
      end

      if file_valid
        File.open(output_filepath, "w+") do |output_file|
          begin
            case format
            when "csv", "CSV"
              if output_filepath != resource_filepath
                `cp -a #{resource_filepath} #{output_filepath}`
              end
            when "json", "JSON"
              output_file.write(generate_json(resource_file))
            when "sql", "SQL"
              table_data = retrieve_table_data(resource_file)
              generate_sql_file(table_data[:locations],table_data[:countries], output_file, dbms_type)
            else
              abort("Format not available")
            end
          rescue => e
            abort(e.message)
          end
        end
      else
        abort("Resource file not valid")
      end
    end
  else
    abort("Resource file not found")
  end
end


options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: geocoordinate_retriever_and_formatter.rb [options]"

  opts.on("-F", "--force", "Force the download of all of the latest geocoordinate resources") do |f|
    options[:force] = true
  end

  opts.on("-d", "--directory", "The directory where the geocoordinate resources are stored") do |d|
    options[:directory] = d
  end

  opts.on("-o", "--outputfilepath", "Filename for output") do |o|
    options[:outputfilepath] = o
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

  opts.on("-rRESOURCE", "--resourceRESOURCE", "The location of the input geocoordinate file") do |f|
    options[:resource] = f
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end

end.parse!

if options.has_key?(:list)
  case options[:list]
  when "local"
    puts retrieve_local_geocoordinate_resources(directory).sort.join(" ")
  when "diff"
    puts (retrieve_remote_geocoordinate_resources(site) - retrieve_local_geocoordinate_resources(directory)).sort.join(" ")
  when "remote"
    puts retrieve_remote_geocoordinate_resources(site).sort.join(" ")
  else
    puts "Option not available"
  end

  abort()
else
  if options.has_key?(:directory)
    directory = options[:directory]
  end

  if options.has_key?(:outputfilepath)
    output_filepath = options[:outputfilepath]
  end

  if options.has_key?(:resource)
    resource_filepath = options[:resource]
  end

  if options.has_key?(:format)
    if options.has_key?(:dbmstype)
      if available_dbms.include?(options[:dbms_type])
        dbms_type = options[:dbms_type]
        if not options[:format] == "sql"
          abort("Can only specify a DBMS type with SQL format(-t)")
        else
          if available_formats.include?(options[:format])
            format = options[:format]
          else
            abort("Format unavailable")
          end
        end
      else
        abort("DBMS unavailable")
      end
    end
    
    if File.exists?(resource_filepath)
      if options.has_key?(:force)
      #download new/replace all existing resources
        retrieve_geocoordinate_resources(site, directory, true)
        generate_resource_file(resource_filepath, Dir.glob('*').select {|f| File.directory? f}, country_code_mappings)
      else
      #just add the missing resources to the file, keeping the current ones
        retrieve_geocoordinate_resources(site, retrieve_remote_geocoordinate_resources(site) - retrieve_local_geocoordinate_resources(directory), false)
      end
    else
      if options.has_key?(:resource)
        abort("Missing resource file")
      else
        retrieve_geocoordinate_resources(site, retrieve_remote_geocoordinate_resources(site) - retrieve_local_geocoordinate_resources(directory), false)
        generate_resource_file(resource_filepath, retrieve_remote_geocoordinate_resources(site) - retrieve_local_geocoordinate_resources(directory), country_code_mappings)
      end
    end
    create_data(format, resource_filepath, output_filepath,dbms_type)

  else
    if options.has_key?(:dbmstype)
      abort("Can only specify a DBMS type with SQL format (-t)")
    end
  end
end
