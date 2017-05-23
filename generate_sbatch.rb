#!/usr/bin/env ruby
require 'artii'
require 'colorize'
require 'filesize'

# don't throw an error on exit
trap "SIGINT" do
  puts "\n Quitting..."
  exit 130
end

#  __ __              __                     
# (_ |__) _ |_ _|_   / _  _ _  _ _ _ |_ _  _ 
# __)|__)(_||_(_| )  \__)(-| )(-| (_||_(_)|  
# 
# 
# quick implementation of creating a SBatch Job Generator
# 
# 

begin
	
	# splash screen
	artii = Artii::Base.new({})
	puts artii.asciify('SBatch Generator').blue
	# directions
	puts "Generate a #{"SLURM bash script ".yellow} to run jobs on the rnet research cluster\n\n"
	# puts "Run this command with -h for a list of more options\n\n"
	printf "Press "
	printf "Ctrl + C ".red
	puts "at any time to quit\n\n"


	# create time element
	t = Time.now 
	# get the script name
	printf "Enter a new SBatch script #{"job name".green} ( leave blank for `sbatch_[date]` default ): "
	job_name = gets.chomp
	job_name = "sbatch_#{t.strftime("%Y_%m_%d")}" if job_name.empty?

	# our list of nodes
	nodes = []
	# list of node header elements
	node_header = []

	# get all the cluster info
	# contents = `sinfo -S partitionname -O partitionname,available,cpus,cpusstate,defaulttime,freemem,memory`
	# # for testing only 
	file = File.open("sinfo_output", "rb")
	contents = file.read
	# put all the clusters into a selectable object
	contents.split("\n").each_with_index do |line, index| 
		line = line.split("\s")
		# get our header rows
		if index < 1
			node_header = line 
			next
		end
		# create a node
		nodes.push({
			name: line[0],
			available: line[1],
			cpus: line[2].sub('+', '').to_i,
			cpus_state: line[3].split("/"),
			time_limit: line[4],
			free_memory: line[5].to_i,
			total_memory: line[6].sub('+', '').to_i
		})
	end
	# list our nodes
	nodes.each.with_index(1) do |node, index|  
		puts "#{index}) #{node[:name]}".green
		free = (node[:cpus_state][1].to_f / (node[:cpus_state][0].to_f.nonzero? || node[:cpus_state][1].to_f) ) * 100
		puts "[ CPU => #{node[:cpus]} (#{free.to_i} % free), MEM => #{Filesize.from("#{node[:total_memory]} MB").to_s("GB")} (#{Filesize.from("#{node[:free_memory]} MB").to_s("GB")} free), TIME LIMIT => #{node[:time_limit]} ]".colorize((:red unless node[:available].eql? 'up'))
		puts "-----------------------------"
	end

	# get the cluster to use
	# node_selection.is_a? Numeric and 
	node_selection = 0
	until (1..nodes.size).include? node_selection
		printf "\nSelect a cluster from the list above to run on (number): "
		node_selection = gets.chomp.to_i
	end

	# get the node
	selected_node = nodes[node_selection - 1]

	# get cpu usage
	cpus = 0
	until (1..selected_node[:cpus]).include? cpus
		puts "\nThe #{selected_node[:name]} node has #{selected_node[:cpus].to_s.green} total CPUs available."
		printf "Number of CPUs to use: "
		cpus = gets.chomp.to_i
	end

	# get the memory
	memory = 0
	until (1..selected_node[:total_memory]).include? memory.to_i and memory =~ /\d*[M|G]/
		# get memory size
		mem_gb = Filesize.from(selected_node[:total_memory].to_s + "MB").to_s("GB")
		# print memory
		puts "\n#{"#{selected_node[:total_memory]} MB".green} (#{mem_gb.green}) total memory is available."
		printf "Amount of Memory to use (suffix #{"M".green} for megabytes and #{"G".green} for gigabytes): "
		memory = gets.chomp.upcase
		memory = memory.gsub(/\s/, '')
	end

	# figure out time
	selected_node[:time_limit]
	days = selected_node[:time_limit].slice!(/\d*-/)
	hours, minutes, seconds = selected_node[:time_limit].split(":")

	time = ""
	# make sure it's in a close enough format
	until time =~ /(\d-)?\d{1,2}(:\d{1,2})*/
		printf "\nThe maximum time alloted is"
		printf " #{days[/\d*/]} days".green if days 
		printf " #{hours} hours".green if hours and hours != '00'
		printf " #{minutes} minutes".green if minutes and minutes != '00'
		printf " #{seconds} seconds".green if seconds and seconds != '00'
		puts "."
		printf  "Estimate job completion time? (days-hour:min:seconds): "
		time = gets.chomp
	end

	# check if notifications
	printf "\nWould you like email notification for you job's status? (yes / no): "
	updates = gets.chomp.downcase.match(/^y/)


	email = ""
	update_types = ""
	if updates
		until not email.empty? 
			printf "Enter your #{"email".green}: "
			email = gets.chomp.downcase
		end

		until %w( BEGIN END FAIL ALL).include? update_types
			puts "Select the job status for notifications"
			printf "select #{"BEGIN END FAIL".green} or #{"ALL".green}: "
			update_types = gets.chomp.upcase
		end
	end


	# get the output name
	puts "\nEnter the #{"command".green} to execute."
	puts "If you need to execute multiple lines, it is recommended to leave this blank and edit the #{"#{job_name}.sh".green} file after creation."
	printf "Command: "
	code_snip = gets.chomp

	# get the output name
	puts "\nThe results from the commands above will be placed in an output file."
	printf "Enter an output file name ( leave blank for `#{job_name}_[job-id].out` default ): "
	output_file = gets.chomp
	output_file = "#{job_name}_%j.out" if output_file.empty?


	File.open("#{job_name}.sh", 'w') do |f|
		f.write("#!/bin/bash")
		f.write("
## sbatch params:
## more params found here https://slurm.schedmd.com/sbatch.html
## ----------------------------
#SBATCH --partition=#{selected_node[:name]}
#SBATCH --time=#{time}
#SBATCH --cpus-per-task=#{cpus} 
#SBATCH --mem=#{memory}
#SBATCH --job-name=#{job_name}
#SBATCH --output=#{output_file}")
		if updates
			f.write("
#SBATCH --mail-type=#{update_types}
#SBATCH --mail-user=#{email}")
		end
		f.write("				
## place your code to run below:
## ----------------------------
## example: 
## echo 'Hello World!'
#{code_snip}
			")
	end

	puts "----------------------------"
	puts "\n\nThe file #{"#{job_name}.sh".yellow} has been written to: #{Dir.pwd.yellow}"
	puts "You may run this job with the command: #{"sbatch #{job_name}.sh".yellow}"
rescue Exception => e
	puts e
end