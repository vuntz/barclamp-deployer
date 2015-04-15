# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

os_token="#{node[:platform]}-#{node[:platform_version]}"
Chef::Log.info("Running on #{os_token}")

file "/tmp/.repo_update" do
  action :nothing
end

unless CrowbarHelper.in_sledgehammer?(node)
  case node["platform"]
  when "ubuntu","debian"
    repositories = node["provisioner"]["repositories"][os_token]
    cookbook_file "/etc/apt/apt.conf.d/99-crowbar-no-auth" do
      source "apt.conf"
    end
    file "/etc/apt/sources.list" do
      action :delete
    end
    repositories.each do |repo,urls|
      case repo
      when "base"
        template "/etc/apt/sources.list.d/00-base.list" do
          variables(:urls => urls)
          notifies :create, "file[/tmp/.repo_update]", :immediately
        end
      else
        template "/etc/apt/sources.list.d/10-barclamp-#{repo}.list" do
          source "10-crowbar-extra.list.erb"
          variables(:urls => urls)
          notifies :create, "file[/tmp/.repo_update]", :immediately
        end
      end
    end
    bash "update software sources" do
      code "apt-get update"
      notifies :delete, "file[/tmp/.repo_update]", :immediately
      only_if { ::File.exists? "/tmp/.repo_update" }
    end
    package "rubygems"
  when "redhat","centos"
    maj,min = node[:platform_version].split('.',2)
    repositories = Range.new(0,min.to_i).to_a.reverse.map{|v|
      provisioner["provisioner"]["repositories"]["#{node[:platform]}-#{maj}.#{v}"] rescue nil
    }.compact.first
    bash "update software sources" do
      code "yum clean expire-cache"
      action :nothing
    end
    repositories.each do |repo,urls|
      template "/etc/yum.repos.d/crowbar-#{repo}.repo" do
        source "crowbar-xtras.repo.erb"
        variables(:repo => repo, :urls => urls)
        notifies :create, "file[/tmp/.repo_update]", :immediately
      end
    end
     bash "update software sources" do
      code "yum clean expire-cache"
      notifies :delete, "file[/tmp/.repo_update]", :immediately
      only_if { ::File.exists? "/tmp/.repo_update" }
    end
  end

  if node["platform"] != "suse" and node["platform"] != "windows"
    provisioner_settings = CrowbarConfig.fetch("core", "provisioner")
    provisioner_url = "#{provisioner_settings["web"]["protocol"]}://#{provisioner_settings["web"]["host"]}:#{provisioner_settings["web"]["port"]}"
    template "/etc/gemrc" do
      variables(:source_url => provisioner_url)
      mode "0644"
    end
  end
end
