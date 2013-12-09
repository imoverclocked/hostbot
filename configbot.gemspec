# WARNING : RAKE AUTO-GENERATED FILE.  DO NOT MANUALLY EDIT!
# RUN : 'rake gem:update_gemspec'

Gem::Specification.new do |s|
  s.authors = ["Tim Spriggs", "Kenny Fine"]
  s.bindir = "bin"
  s.description = "CONFIGBOT is an XMPP/Jabber bot based on XMPP4R."
  s.email = "sys@pirl.lpl.arizona.edu"
  s.executables = ["configbot.rb", "muppetbot.rb", "servicebot.rb"]
  s.files = ["Rakefile",
  "lib/configbot/acl.rb",
  "lib/configbot/commands.rb",
  "lib/configbot/aggrhandler.rb",
  "lib/configbot/confighandler.rb",
  "lib/configbot/ptyhandler.rb",
  "lib/configbot/bghandler.rb",
  "lib/configbot/conf.rb",
  "lib/configbot/puppet_commands.rb",
  "lib/configbot/groups.rb",
  "lib/configbot/check_command.rb",
  "lib/configbot/basehandler.rb",
  "lib/configbot/configbot_commands.rb",
  "lib/configbot/service_commands.rb",
  "bin/muppetbot.rb",
  "bin/configbot.rb",
  "bin/servicebot.rb",
  "configbot.gemspec",
  "setup.rb",
  "test/ts_configbot.rb"]
  s.has_rdoc = false
  s.homepage = "http://pirlwww.lpl.arizona.edu/"
  s.loaded = false
  s.name = "configbot"
  s.platform = "ruby"
  s.require_paths = ["."]
  s.required_ruby_version = ">= 1.8.4"
  s.required_rubygems_version = ">= 0"
  s.rubyforge_project = "configbot"
  s.rubygems_version = "1.3.1"
  s.specification_version = 2
  s.summary = "CONFIGBOT is an XMPP/Jabber bot based on XMPP4R."
  s.version = "0.0.17"
  s.add_dependency('xmpp4r', '>=0.5')
  s.add_dependency('file-tail', '>=1.0.10')
end
