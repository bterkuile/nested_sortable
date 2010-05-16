# Install hook code here
require 'fileutils'
include FileUtils
cp_r File.join(__FILE__, 'javascripts'), File.join(Rails.root, 'public', 'javascripts')
cp_r File.join(__FILE__, 'stylesheets'), File.join(Rails.root, 'public', 'stylesheets')
