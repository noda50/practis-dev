require 'pp'
require 'rexml/document'

module FileGenerator

	# generate generation file for crowdwalk
	def self.genearete_gen()
		
	end

	# generate scenario file for crowdwalk
	def self.generate_scenario()
		
	end

	# generate property file for crowdwalk
	def self.generate_property(	dirname="2links", filename="property.xml", map="map-width-1", 
															gas="gas", gen="gen", scenario="scenario", seed=2525)
		doc = REXML::Document.new
		doc << REXML::XMLDecl.new('1.0', 'UTF-8')
		doc << REXML::DocType.new("properties", "SYSTEM \"http://java.sun.com/dtd/properties.dtd\"")

		# sample/kitakyushu
		properties = doc.add_element("properties", {})
		properties.add_element("comment").add_text "NetmasCuiSimulator"
		properties.add_element("entry", {'key' => 'debug'}).add_text "false"
		properties.add_element("entry", {'key' => 'io_handler_type'}).add_text "none"
		mapfile = dirname + "/" + map + ".xml"
		properties.add_element("entry", {'key' => 'map_file'}).add_text mapfile
		gasfile = dirname + "/" + gas + ".csv"
		properties.add_element("entry", {'key' => 'pollution_file'}).add_text gasfile
		genfile = dirname + "/" + gen + ".csv"
		properties.add_element("entry", {'key' => 'generation_file'}).add_text genfile
		scenariofile = dirname + "/" + scenario + ".csv"
		properties.add_element("entry", {'key' => 'scenario_file'}).add_text scenariofile
		properties.add_element("entry", {'key' => 'timer_enable'}).add_text "false"
		properties.add_element("entry", {'key' => 'timer_file'}).add_text "/tmp/timer.log"
		properties.add_element("entry", {'key' => 'interval'}).add_text "0"
		# properties.add_element("entry", {'key' => 'addr'})#.add_text ""
		# properties.add_element("entry", {'key' => 'port'})#.add_text ""
		# properties.add_element("entry", {'key' => 'serialize_file'}).add_text "/tmp/serialized.xml"
		# properties.add_element("entry", {'key' => 'serialize_interval'}).add_text "60"
		# properties.add_element("entry", {'key' => 'deserialized_file'}).add_text "/tmp/serialized.xml"
		properties.add_element("entry", {'key' => 'randseed'}).add_text "#{seed}"
		properties.add_element("entry", {'key' => 'random_navigation'}).add_text "false"
		properties.add_element("entry", {'key' => 'speed_model'}).add_text "density"
		# properties.add_element("entry", {'key' => 'density_density_speed_model_macro_timestep'}).add_text "10"
		properties.add_element("entry", {'key' => 'time_series_log'}).add_text "false"
		properties.add_element("entry", {'key' => 'time_series_log_path'}).add_text "tmp"
		properties.add_element("entry", {'key' => 'damage_speed_zero_log'}).add_text "true"
		properties.add_element("entry", {'key' => 'damage_speed_zero_log_path'}).add_text "tmp/damage_speed_zero.csv"
		properties.add_element("entry", {'key' => 'time_series_log_interval'}).add_text "1"
		properties.add_element("entry", {'key' => 'loop_count'}).add_text "1"
		properties.add_element("entry", {'key' => 'exit_count'}).add_text "0"
		properties.add_element("entry", {'key' => 'all_agent_speed_zero_break'}).add_text "true"
		# properties.add_element("entry", {'key' => 'exit_count'}).add_text "1200"

		# properties.add_element("entry", {'key' => ''}).add_text ""
		# doc.write STDOUT

		doc.write(File.new(filename, "w"))
	end
end

# for debug 
if __FILE__ == $0
	p "debug: property file generation"
	FileGenerator.generate_property

end