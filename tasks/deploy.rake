# Please view README before using
# RDEPLOY

######################

task :local_settings => [:environment] do
   
  deploy_file = File.join(RAILS_ROOT, 'config', 'deploy.yml')
  raise "#{deploy_file} missing" unless File.exists? deploy_file
  @settings = YAML::load(File.open(deploy_file))[RAILS_ENV]
  @settings['environment'] ||= RAILS_ENV
  @settings['ssh_cmd'] ||= 'ssh'
  @settings['scp_cmd'] ||= 'scp'
  @settings['git_uri'] ||= "~/git/:app_name"
  @settings['git_repos'] ||= 'master'
  @settings['pretend'] ||= false
  @settings['compress_cmd'] ||= "zip -9r :dest.zip :src -x ':src/.git/*'"
  inject_symbol_values(@settings)
  
end

# replace any symbols in string values with other values from the settings file
def inject_symbol_values(settings)
  %w(deploy_to remote_backup_path).each do |target_key|
    settings.each do |source_key,source_value|
      settings[target_key].gsub!(':' + source_key.to_s, source_value) if source_value.is_a? String
    end
  end
end

######################

task :bootstrap => [:environment] do
  %w(database.yml settings.yml).each do |file|
    unless File.exists? File.join(RAILS_ROOT, 'config', file)
      system "cp #{File.join(RAILS_ROOT, 'config', file.gsub('.','.example.'))} #{File.join(RAILS_ROOT, 'config', 'database.yml')}"
    end
  end
end

#### APP ####

# Restart application (mod_rails)
namespace :app do
  task :restart => [:environment] do
    run "touch #{RAILS_ROOT}/tmp/restart.txt"
  end
end

#### DB ####

namespace :db do
  task :backup => [:environment] do
    # TODO: mysqldump symlink 'latest' to file
    # remote_run 'mysqldump DATABASE > @settings['remote_backup_path']/abc_timestamp.sql'
    # rm exisitng symlink
    # ln -s A B
  end  
end

#### CODE ####

namespace :code do
  task :push => [:load_control_settings] do
    run "git push origin #{@settings['git_repos']}"
  end

  task :pull do
    run "git pull origin master"
  end

  task :auto_commit do
    run ['git add .',
      'git commit -m "Auto Commit"']
  end

  task :commit_and_push => [:auto_commit, :push]      
end

# wrapper around system allowing array of commands to be passed
def run(lines)
  lines = [lines] unless lines.is_a? Array
  command = lines.join(' && ')
  puts command
  system command
end

namespace :server do
  
  # Load and parse our settings
  task :server_environment => [:environment] do
        deploy_file = File.join(RAILS_ROOT, 'config', 'deploy.yml')
        raise "#{deploy_file} missing" unless File.exists? deploy_file
        @settings = YAML::load(File.open(deploy_file))[RAILS_ENV]
        @settings['environment'] ||= RAILS_ENV
        @settings['ssh_cmd'] ||= 'ssh'
        @settings['scp_cmd'] ||= 'scp'
        @settings['git_uri'] ||= "~/git/:app_name"
        @settings['git_repos'] ||= 'master'
        @settings['pretend'] ||= false
        @settings['compress_cmd'] ||= "zip -9r :dest.zip :src -x ':src/.git/*'"
        inject_symbol_values(@settings)
  end

  # replace any symbols in string values with other values from the settings file
    def inject_symbol_values(settings)
      %w(deploy_to remote_backup_path).each do |target_key|
        settings.each do |source_key,source_value|
          settings[target_key].gsub!(':' + source_key.to_s, source_value) if source_value.is_a? String
        end
      end
    end

  task :debug => [:server_environment] do
    puts @settings.inspect
  end
  

  # Creates a copy of all rake task inside this namespace except they are run on the server instead of locally
  # eg. rake server:db:create will create the database on the server
  Rake.application.tasks.reject { |task| task.name.include? 'server' or task.name == 'environment'}.each do |task|
    task task.name.to_sym => [:server_environment] do
      remote_task task.name
    end
  end

  desc 'Setup folders and versioning on server'
  task :setup => [:server_environment] do
    remote_run [
      "mkdir #{@settings['deploy_to']}",
      "cd #{@settings['deploy_to']}",
      "touch ../#{@settings['app_name']}_#{@settings['environment']}_last_deploy.txt",
      "git init",
      "git remote add origin #{@settings['git_uri']}"
      ]
  end

  desc 'Teardown on server'
  task :teardown => [:server_environment] do
    remote_run ["mv #{@settings['deploy_to']} #{@settings['deploy_to']}/../#{@settings['app_name']}_#{@settings['environment']}_#{Time.now.strftime('%d%m%Y%H%M%S')}"]
  end

  desc 'Backup deployment'
  task :backup => [:server_environment] do
    remote_run @settings['compress_cmd'].gsub(':dest', "#{@settings['deploy_to']}/../#{@settings['app_name']}_#{@settings['environment']}_#{Time.now.strftime('%d%m%Y%H%M%S')}").gsub(':src', @settings['deploy_to'])
  end

  desc 'Update code on server with latest from git'
  task :update_code => [:server_environment] do
    remote_task 'code:pull'
#    remote_run ["cd #{@settings['deploy_to']}", "git pull origin #{@settings['git_repos']}"]
  end 

  desc 'Pull the UI changes in to git'
  task :get_ui => [:server_environment] do
    remote_task 'code:commit_and_push'
#    remote_run ["cd #{@settings['deploy_to']}", "git add .", "git commit -m 'UI Changes (via FTP)'", "git push"]
    puts "You now need to pull these changes (if any) from git to get them locally"
  end    
  
  task :deploy => [:update_code, :restart_app]
  task :setup_and_bootstrap => [:setup, :bootstrap]

  namespace :db do
    desc 'Download latest backup from server'
    task :download do
      remote_task('db:backup') # will execution wait for this to finish?
      get_file(@settings['server']['backup_path'] + '/latest', @settings['local']['backup_path'])
    end
  end

  private

  # run a command on the server
  # TODO: parse all lines like inject_symbol_values so we can just pass "cd :deploy_to" as a line
  def remote_run(lines)
    lines = [lines] unless lines.is_a? Array
    command = @settings['ssh_cmd'] + ' ' + '"' + lines.join(' && ') + '"'
    puts command
    system command unless @settings['pretend']
  end

  # run a rake task on the server
  def remote_task(task)
    remote_run ["cd #{@settings['deploy_to']}", "rake #{task} RAILS_ENV=#{RAILS_ENV}"]
  end

  # get a file from the server (eg. backup)
  def get_file(remote_file, local_file)
    # scp domain.com:remote_file local_file
  end
end