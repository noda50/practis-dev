require 'pp'
require 'rexml/document'
require 'csv'

module FileGenerator

GENERATION_PATTERN = ["EACH", "RANDOM", "EACHRANDOM", "RANDOMALL", 
											"TIMEEVERY", "LINER_GENERATE_AGENT_RATIO"]

	# 
	def self.generate_map(dirname="2links", filename="map.xml")
		doc = REXML::Document.new
		doc << REXML::XMLDecl.new('1.0', 'UTF-8', 'no')
		doc << REXML::DocType.new("properties", "SYSTEM \"http://java.sun.com/dtd/properties.dtd\"")
		# properties.add_element("entry", {'key' => ''}).add_text ""
		# doc.write STDOUT

		doc.write(File.new(filename, "w"))
	end

	# generate generation file for crowdwalk
	def self.genearete_gen(dirname="2links", filename="gen.csv")
		CSV.open(filename, "w") do |csv|
			csv << []
		end
	end

	# generate scenario file for crowdwalk
	def self.generate_scenario(dirname="2links", filename="scenario.csv")
		CSV.open(filename, "w") do |csv|
			csv << [1, 0, "START", " ","18:00", " ", " "]#start"
		end
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

	private
	# for moji?
	def generation_pattern(filename, ratioA, ratioB, ratio, model)
		baseWString = "TIMEEVERY,WEST_STATION_LINKS,18:00:00,18:09:00,60,60,"
    baseEString = "TIMEEVERY,EAST_STATION_LINKS,18:00:00,18:09:00,60,60,"
    out.write(baseWString + ((int)(ratioA * 1 * ratio)).toString() + "," + model + ",EAST_STATION_N_NODES,POINT_A,E_POINT_A\n")
    out.write(baseWString + ((int)(ratioA * 1 * ratio)).toString() + "," + model + ",EAST_STATION_MN_NODES,POINT_A,E_POINT_B\n")
    out.write(baseWString + ((int)(ratioA * 1 * ratio)).toString() + "," + model + ",EAST_STATION_MS_NODES,POINT_A,E_POINT_C\n")
    out.write(baseWString + ((int)(ratioA * 1 * ratio)).toString() + "," + model + ",EAST_STATION_S_NODES,POINT_A,E_POINT_D\n")
    out.write(baseEString + ((int)(ratioB * 1 * ratio)).toString() + "," + model + ",WEST_STATION_N_NODES,POINT_B,W_POINT_A\n")
    out.write(baseEString + ((int)(ratioB * 1 * ratio)).toString() + "," + model + ",WEST_STATION_MN_NODES,POINT_B,W_POINT_B\n")
    out.write(baseEString + ((int)(ratioB * 1 * ratio)).toString() + "," + model + ",WEST_STATION_MS_NODES,POINT_B,W_POINT_C\n")
    out.write(baseEString + ((int)(ratioB * 1 * ratio)).toString() + "," + model + ",WEST_STATION_S_NODES,POINT_B,W_POINT_D\n")
    out.write(baseWString + ((int)((1.0 - ratioA) * 1 * ratio)).toString() + "," + model + ",EAST_STATION_N_NODES,POINT_C,E_POINT_A\n")
    out.write(baseWString + ((int)((1.0 - ratioA) * 1 * ratio)).toString() + "," + model + ",EAST_STATION_MN_NODES,POINT_C,E_POINT_B\n")
    out.write(baseWString + ((int)((1.0 - ratioA) * 1 * ratio)).toString() + "," + model + ",EAST_STATION_MS_NODES,POINT_C,E_POINT_C\n")
    out.write(baseWString + (((int)(1.0 - ratioA) * 1 * ratio)).toString() + "," + model + ",EAST_STATION_S_NODES,POINT_C,E_POINT_D\n")
    out.write(baseEString + (((int)(1.0 - ratioB) * 1 * ratio)).toString() + "," + model + ",WEST_STATION_N_NODES,POINT_D,W_POINT_A\n")
    out.write(baseEString + (((int)(1.0 - ratioB) * 1 * ratio)).toString() + "," + model + ",WEST_STATION_MN_NODES,POINT_D,W_POINT_B\n")
    out.write(baseEString + (((int)(1.0 - ratioB) * 1 * ratio)).toString() + "," + model + ",WEST_STATION_MS_NODES,POINT_D,W_POINT_C\n")
    out.write(baseEString + (((int)(1.0 - ratioB) * 1 * ratio)).toString() + "," + model + ",WEST_STATION_S_NODES,POINT_D,W_POINT_D\n")
	end
end



# for debug 
if __FILE__ == $0
	p "debug: property file generation"
	FileGenerator.generate_property
	p "debug: scenario file generation"
	FileGenerator.generate_scenario
	p "debug: map file generation"
	FileGenerator.generate_map
end