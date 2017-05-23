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
	printf "Generate a "
	printf "SLURM bash script ".yellow
	puts "to run jobs on the rnet research cluster\n\n"
	# puts "Run this command with -h for a list of more options\n\n"
	printf "Press "
	printf "Ctrl + C ".red
	puts "at any time to quit\n\n"


	# create time element
	t = Time.now 
	# get the script name
	printf "Enter a new SBatch script job name ( leave blank for `sbatch_[date]` default ): "
	job_name = gets.chomp
	job_name = "sbatch_#{t.strftime("%Y_%m_%d")}" if job_name.empty?

	# our list of nodes
	nodes = []
	# list of node header elements
	node_header = []

	# get all the cluster info
	contents = `sinfo -S partitionname -O partitionname,available,cpus,cpusstate,defaulttime,freemem,memory`
	# # for testing only 
	# file = File.open("sinfo_output", "rb")
	# contents = file.read
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
	nodes.each_with_index do |node, index|  
		puts "#{index}) #{node[:name]}".green
		free = (node[:cpus_state][1].to_f / (node[:cpus_state][0].to_f.nonzero? || node[:cpus_state][1].to_f) ) * 100
		puts "[ CPU => #{node[:cpus]} (#{free.to_i} % free), MEM => #{Filesize.from("#{node[:total_memory]} MB").to_s("GB")} (#{Filesize.from("#{node[:free_memory]} MB").to_s("GB")} free), TIME LIMIT => #{node[:time_limit]} ]".colorize((:red unless node[:available].eql? 'up'))
		puts "-----------------------------"
	end

	# get the cluster to use
	# node_selection.is_a? Numeric and 
	node_selection = 0
	until (1..nodes.size).include? node_selection
		printf "\nSelect a cluster to run on (number): "
		node_selection = gets.chomp.to_i
	end

	# get the node
	selected_node = nodes[node_selection]

	# get cpu usage
	cpus = 0
	until (1..selected_node[:cpus]).include? cpus
		printf "\nThe #{selected_node[:name]} node has "
		printf "#{selected_node[:cpus]} ".green
		puts "total CPUs available."
		printf "Number of CPUs to use: "
		cpus = gets.chomp.to_i
	end

	# get the memory
	memory = 0
	until (1..selected_node[:total_memory]).include? memory.to_i and memory =~ /\d*[M|G]/
		printf "\n#{selected_node[:total_memory]}".green
		printf " MB ("
		printf "#{Filesize.from("#{selected_node[:total_memory]} MB").to_s("GB")}".green
		puts ") total memory is available."
		printf "Amount of Memory to use (suffix M for megabyes and G for gigabytes): "
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


	# get the output name
	puts "\nSBatch commands to execute:"
	printf "If you need to execute more than one command, it is recommended to leave this blank and edit the "
	printf "#{job_name} ".green
	puts "file after creation."
	printf "SBatch Commands: "
	code_snip = gets.chomp

	# get the output name
	printf "\nEnter an output file name ( leave blank for `#{job_name}_[job-id].out` default ): "
	output_file = gets.chomp
	output_file = "#{job_name}_%j.out" if output_file.empty?


	File.open(job_name, 'w') do |f|
		f.write("#!/bin/bash

## sbatch params:
## more params found here https://slurm.schedmd.com/sbatch.html
## ----------------------------
#SBATCH --partion=#{selected_node[:name]}
#SBATCH --time=#{time}
#SBATCH --cpus-per-task=#{cpus} 
#SBATCH --mem=#{memory}
#SBATCH --job-name=#{job_name}
#SBATCH --output=#{output_file}

## place your code to run below:
## ----------------------------
## example: 
## echo 'Hello World!'
#{code_snip}


			")
	end

rescue Exception => e
	puts e
end