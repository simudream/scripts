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
          `wget #{base_uri + link["href"]}`
          `unzip *.zip`
          `rm *.zip`
        end
      end
    end
  end
end

#get a list of directories and parse the contents, writing to a compiled geocoordinate file.
#TODO handle file errors
def generate_resource_file(filename)
  resource_file = open_file(filename, 'w+')
  resource_file.puts "Latitude,Longitude,Location,Country Code"
  
  directories = Dir.glob('*').select {|f| File.directory? f}

  directories.each do |directory|
    #remove the headers
    system('tail -n +2 ' + directory + '/' + directory + '.txt' + ' > ' + directory + '/' + directory)
    #write the new file
    File.foreach(fileLocation) { |line| 
      components = line.split "\t"
      geocoordFile.puts components[3] + "," + components[4] + "," + components[22] + "," + directory.upcase
    }
    File.delete(directory + '/' + directory)
  end

  resource_file.close
end

#TODO: put in try to handle file errors
def open_file(filepath, state)
  return File.open(filepath, state)
end

def generate_json(resource_file, out_file)
end

def generate_sql(resource_file, out_file)
end

#TODO: check if resource_file exists
def format_data(format, resource_filepath, out_filepath)
   resource_file = open_file(resource_filepath, 'r')
   out_file = open_file(out_filepath, 'w+')

   case format
   when "csv", "CSV"
     if out_file != resource_file
       `cp -A #{resource_file} #{out_file}`
     end
   when "json", "JSON"
     generate_
   when "sql", "SQL"

   else
     return "Format not available"
   end

   resource_file.close
   out_file.close
end


class Parser
  def self.parse(options)
    args = {}

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: example.rb [options]"

      opts.on("-r", "--retrieve", "Retrieve the geocoordinate resources") do |r|
        args["retrieve"] = True
      end

      opts.on("-o", "--outputfilepath", "Filename for output") do |o|
        args["outputfilepath"] = o
      end

      opts.on("-fFORMAT", "--formatFORMAT", "Save the geocoordinate resources in the available format") do |f|
        args["format"] = f
      end

      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(options)
    return args
  end
end

options = Parser.parse(ARGV)
site = 'http://earth-info.nga.mil/gns/html/namefiles.html'
resource_file = "geocoords"

