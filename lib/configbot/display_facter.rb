#!/usr/bin/ruby1.8
require "yaml"
yaml_files = {}
dir = "/var/lib/puppet/yaml/facts/"
all_files = Dir.new(dir).entries
all_files.sort!

all_files.each do |nf|
	if File.file?("#{dir}#{nf}")
		shortname = nf.split(".")[0]
		tmp_file = YAML::load_file("#{dir}#{nf}")
		if yaml_files.has_key?(shortname)
			o =  yaml_files[shortname].ivars['expiration']
			n =  tmp_file.ivars['expiration']
			if (DateTime.parse("#{n}") > DateTime.parse("#{o}") )
				yaml_files[shortname] = tmp_file
			end
		else
			yaml_files[shortname] = tmp_file
		end
	end
end
if !(ARGV.include?("-n") or ARGV.include?("-p"))
	print "USAGE: ask -n node
		ask -p property
		ask -n node -p property"
else
	ARGV.include?("-n") ? yaml = ARGV[ARGV.index("-n")+1].split(","): yf = yaml_files
	if (!yf)
		yf = {}
		if (yaml[0] == "all")
		  yf = yaml_files
		else
		  yaml.each do |y|
			 yf[y] = yaml_files[y.split(".")[0]]		
		  end
		end
	end
	yf = yf.sort
	ARGV.include?("-p") ? properties = ARGV[ARGV.index("-p")+1].split(","): properties = "all"
	ultra_display = {}
	display = {}
	if (yf != nil)
		yf.each do |y|
			if properties == "all"
				y[1].ivars['values'].each do |val|
					puts "#{y[0]}: #{val[0]}: #{val[1]}"
				end
			else
				properties.each do |prop| 
						if y[1].ivars['values'].include?(prop) and prop != nil
							prop_val = y[1].ivars['values'][prop]
						elsif y[1].ivars['values'].include?(prop.to_sym) and prop != nil
							prop_val = y[1].ivars['values'][prop.to_sym]
						else
							prop_val = "Not Found"
						end
						if (!display.key?(prop))
							display[prop] = Hash.new
						end
						if (!display[prop].key?(prop_val))
							display[prop][prop_val] = Array.new
						end
						display[prop][prop_val].push(y[0])
				end
		end
	end
	else 
		puts "Node #{ARGV[ARGV.index("-n")+1]} could not be found"
	end
				display.each do |prop, display|
					puts "#{prop}:"
					d = display.sort
					d.each do |prop_val, node|
						print node.join(", ")
						#node.each do |n|
						#	print "#{n},  "
						#end
						print ":\t#{prop_val} "
						print "\n"
					end
					puts ""
				end
end
