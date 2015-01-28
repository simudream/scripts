require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'optparse'

#loop through tables and gather uris for geocoordinate resources
#TODO: handle http errors
#TODO: handle command errors
def retrieve_geocoordinate_resources(site)
  base_uri = site[0..site.rindex(/\//)]
  #resource_uris = []
  page = Nokogiri::HTML(open(site))

  #puts page.class   # => Nokogiri::HTML::Document
  links = page.css('table tr td a')
  links.each do |link|
    #Nokogiri::XML::Element method
    if link.key?("href")
      if link["href"].length > 7 and link["href"][0..7] == "cntyfile"
        if link["href"][0] != "#"
          link_string = link["href"].to_s
          link_string = link_string[9..-1]
          `rm #{link_string}`
          `wget #{base_uri + link["href"]}`
          `mkdir #{link_string[0..link_string.index(".") - 1]}`
          `unzip #{link_string} #{link_string[0..link_string.index(".") - 1]}`
          `rm #{link_string}`
        end
      end
    end
  end
end

def retrieve_country_code_mappings(site)
  table_items = []
  country_code_mappings = {}
  page = Nokogiri::HTML(open(site))

  tds = page.css('table tr td')
  td.each do |td|
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
def generate_resource_file(output_filename, country_code_mappings)
  resource_file = open_file(output_filename, 'w+')
  resource_file.puts "Latitude,Longitude,Location,Country Code,Country Name"
  geocoord_file = open_file(output_filename,"r")
  File.open(resource_filepath, "r") do |geocoord_file|
    directories = Dir.glob('*').select {|f| File.directory? f}

    directories.each do |directory|
      #remove the headers
      system('tail -n +2 ' + directory + '/' + directory + '.txt' + ' > ' + directory + '/' + directory)
      #write the new file
      File.foreach(fileLocation) { |line| 
        components = line.split "\t"
        geocoord_file.puts components[3] + "," + components[4] + "," + components[22] + "," + directory.upcase, country_code_mappings[directory.upcase]
      }
      File.delete(directory + '/' + directory)
    end
  end

  resource_file.close
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

#TODO: generate code for multiple dbms using insert statements 
def generate_sql(resource_file)
end

def create_data(format, resource_filepath, output_filepath)
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
              output_file.write(generate_sql(resource_file))
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

  opts.on("-d", "--download", "Force the download of the latest geocoordinate resources") do |d|
    options[:download] = true
  end

  opts.on("-o", "--outputfilepath", "Filename for output") do |o|
    options[:outputfilepath] = o
  end

  opts.on("-fFORMAT", "--formatFORMAT", "Save the geocoordinate resources in the available format") do |f|
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

site = 'http://earth-info.nga.mil/gns/html/namefiles.html'

resource_file = "geocoords"
output_filepath = "output.csv"
format = "CSV"

if options.has_key?(:outputfilepath)
  output_filepath = options[:outputfilepath]
end

if options.has_key?(:format)
  format = options[:format]
end

if options.has_key?(:download)
  retrieve_geocoordinate_resources(site)
  generate_resource(resource_file, retrieve_country_code_mappings(site))
end

if options.has_key?(:resource)
  resource_file = options[:resource]
end

create_data(format, resource_file, output_filepath)
