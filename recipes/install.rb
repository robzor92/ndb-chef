group node['logger']['group'] do
  gid node['logger']['group_id']
  action :create
  not_if "getent group #{node['logger']['group']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

user node['logger']['user'] do
  uid node['logger']['user_id']
  gid node['logger']['group_id']
  shell "/bin/nologin"
  action :create
  system true
  not_if "getent passwd #{node['logger']['user']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

group node['ndb']['group'] do
 gid node['ndb']['group_id']
 action :create
 not_if "getent group #{node['ndb']['group']}"
 not_if { node['install']['external_users'].casecmp("true") == 0 }
end

#
# Need a managed home account, so that the mgmt server user can ssh to the ndbd nodes to start them.
#
user node['ndb']['user'] do
  home node['ndb']['user-home']
  manage_home true
  uid node['ndb']['user_id']
  gid node['ndb']['group']
  action :create
  shell "/bin/bash"
  system true
  not_if "getent passwd #{node['ndb']['user']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

group node['ndb']['group'] do
  action :modify
  members ["#{node['ndb']['user']}", node['logger']['user']]
  append true
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

group node["kagent"]["certs_group"] do
  action :manage
  append true
  excluded_members node['ndb']['user']
  not_if { node['install']['external_users'].casecmp("true") == 0 }
  only_if { conda_helpers.is_upgrade }
end

directory node['ndb']['dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "755"
  action :create
  not_if { File.directory?("#{node['ndb']['dir']}") }
end

directory node['ndb']['root_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

directory node['ndb']['version_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end


link node['ndb']['base_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  to node['ndb']['version_dir']
end

directory node['ndb']['scripts_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "755"
  action :create
end

directory "#{node['ndb']['scripts_dir']}/util" do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "755"
  action :create
end

directory node['data']['dir'] do
  owner 'root'
  group 'root'
  mode '0775'
  action :create
  not_if { ::File.directory?(node['data']['dir']) }
end

directory node['ndb']['data_volume']['root_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

directory node['ndb']['data_volume']['log_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

bash 'Move RonDB logs to data volume' do
  user 'root'
  code <<-EOH
    set -e
    mv -f #{node['ndb']['log_dir']}/* #{node['ndb']['data_volume']['log_dir']}
    rm -rf #{node['ndb']['log_dir']}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node['ndb']['log_dir'])}
  not_if { File.symlink?(node['ndb']['log_dir'])}
end

link node['ndb']['log_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode '0750'
  to node['ndb']['data_volume']['log_dir']
end

directory node['ndb']['BackupDataDir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

directory node['mysql']['version_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "755"
  action :create
end

if node['platform_family'].eql?('rhel')
  package 'ncurses'

  if node['platform_version'] >= '8'
    package 'ncurses-compat-libs'
  end
end

url = node['ndb']['url']
Chef::Log.info "Downloading mysql cluster binaries from #{url}"
base_package_filename = File.basename(node['ndb']['url'])
Chef::Log.info "Into file #{base_package_filename}"
base_package_dirname =  File.basename(base_package_filename, ".tar.gz")
ndb_package_dirname = "#{Chef::Config['file_cache_path']}/#{base_package_dirname}"
cached_package_filename = "#{Chef::Config['file_cache_path']}/#{base_package_filename}"

Chef::Log.info "You should find mysql cluster binaries it in:  #{cached_package_filename}"

# TODO - HTTP Proxy settings
remote_file cached_package_filename do
#  checksum node['ndb']['checksum']
  source url
  mode 0755
  action :create
end

if node['ndb']['bind_cpus'].eql? "true"
  directory "/etc/sysconfig" do
    owner "root"
    group "root"
    mode "755"
    action :create
  end

  file "/etc/sysconfig/irqbalance" do
    owner "root"
    action :delete
  end


  template "/etc/sysconfig/irqbalance" do
    source "irqbalance.ubuntu.erb"
    owner "root"
    group "root"
    mode 0655
  end
end

Chef::Log.info "Unzipping mysql cluster binaries into:  #{base_package_filename}"
Chef::Log.info "Moving mysql cluster binaries to:  #{node['mysql']['version_dir']}"
bash "unpack_mysql_cluster" do
    user "root"
    code <<-EOF
set -e
cd #{Chef::Config['file_cache_path']}
tar -xzf #{cached_package_filename}
mv #{ndb_package_dirname}/* #{node['mysql']['version_dir']}

# http://www.slideshare.net/Severalnines/severalnines-my-sqlclusterpt2013
# TODO: If binding threads to CPU, run the following:
# echo '0' > /proc/sys/vm/swappiness
# echo 'vm.swappiness=0' >> /etc/sysctl.conf

chown -R #{node['ndb']['user']}:#{node['ndb']['group']} #{node['mysql']['version_dir']}
EOF
  not_if { ::File.exists?( "#{node['mysql']['version_dir']}/bin/ndbd" ) }
end


link node['mysql']['base_dir'] do
  owner node['ndb']['user']
  group node['ndb']['group']
  to node['mysql']['version_dir']
end


template "/etc/profile.d/mysql_bin_path.sh" do
  user "root"
  mode 0755
  source "set_path.sh.erb"
end


template "#{node['ndb']['scripts_dir']}/util/kill-process.sh" do
  source "kill-process.sh.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
end



if "#{node['ndb']['aws_enhanced_networking']}" == "true" 
     case node['platform']
     when 'debian', 'ubuntu'
       ndb_ixgbevf "enhanced_ec2_networking" do
         action :install_ubuntu
       end
     when 'redhat', 'centos', 'fedora'
       ndb_ixgbevf "enhanced_ec2_networking" do
         action :install_redhat
       end
     end

end


#
# Nice values are -20..20. Higher values get less CPU (they are 'nicer').
#

ulimit_domain node['ndb']['user'] do
  rule do
    item :priority
    type :hard
    value -19
  end
  rule do
    item :priority
    type :soft
    value -19
  end
  rule do
    item :nice
    type :hard
    value -19
  end
  rule do
    item :nice
    type :soft
    value -19
  end
end

