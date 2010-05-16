# Install hook code here
require 'fileutils'
include FileUtils
puts "Copying javascript files..."
cp_r Dir[File.join(File.dirname(__FILE__), 'javascripts', "*")], File.join(Rails.root, 'public', 'javascripts')
puts "Copying stylesheet"
cp_r Dir[File.join(File.dirname(__FILE__), 'stylesheets', "*")], File.join(Rails.root, 'public', 'stylesheets')
