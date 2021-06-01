# frozen_string_literal: true

require 'rubygems'
require 'bundler'
Bundler.setup(:deploy)

require 'semver'

# Load DSL and Setup Up Stages
require 'capistrano/setup'

# Includes default deployment tasks
require 'capistrano/deploy'

require 'capistrano/scm/git'
install_plugin Capistrano::SCM::Git

require 'capistrano/scm/git-with-submodules'
install_plugin Capistrano::SCM::Git::WithSubmodules

require 'capistrano/rbenv'
require 'capistrano/bundler'
require 'capistrano-db-tasks'
require 'capistrano/shell'

require 'capistrano/rails/migrations'
require 'capistrano/dotenv/tasks'
require 'capistrano/sentry'

require 'capistrano/puma'
install_plugin Capistrano::Puma

# require 'capistrano/rails/console'
# require 'capistrano/master_key'
require 'capistrano/systemd/multiservice'
install_plugin Capistrano::Systemd::MultiService.new_service('puma', service_type: 'user')
install_plugin Capistrano::Systemd::MultiService.new_service('daemon', service_type: 'user')
install_plugin Capistrano::Systemd::MultiService.new_service('amqp_daemon', service_type: 'user')
