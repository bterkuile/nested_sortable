# Install hook code here
require 'fileutils'
include FileUtils
cp_r File.join(File.dirname(__FILE__), 'javascripts'), File.join(Rails.root, 'public', 'javascripts')
cp_r File.join(File.dirname(__FILE__), 'stylesheets'), File.join(Rails.root, 'public', 'stylesheets')
