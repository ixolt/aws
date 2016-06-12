chef_gem 'aws-sdk' do
    compile_time false if respond_to?(:compile_time)
    version ">2.0"
end

require 'rubygems'
require 'aws-sdk'
require 'net/http'


ec2 = Aws::EC2::Client.new(region: "eu-west-1")
metadata_endpoint = 'http://169.254.169.254/latest/meta-data/'
instance = Net::HTTP.get(URI.parse(metadata_endpoint + 'instance-id'))
availability_zone = ec2.describe_instance_status(:instance_ids => [instance]).instance_statuses.first.availability_zone

# prevent multiple ebs getting created
ebs_inuse = ec2.describe_volumes({
    dry_run: false,
    filters: [
        {
            name: "status",
            values: ["in-use"],
        },
        {
            name: "size",
            values: ["#{node['ebs']['size']}" ],
        },
        {
            name: "tag-value",
            values: [ "#{node['ebs']['voltag']}"],
        }
    ]})

if ebs_inuse.volumes[0].volume_id != nil
    puts "Volume already created and in use! "
    abort
end

# should we create a ebs?
ebs = ec2.describe_volumes({
    dry_run: false,
    filters: [
        {
            name: "status",
            values: ["available"],
        },
        {
            name: "size",
            values: ["#{node['ebs']['size']}" ],
        },
        {
            name: "tag-value",
            values: [ "#{node['ebs']['voltag']}"],
        }
    ]})

if ebs.volumes[0] == nil
   # create volumes
   node["ebs"]["device"].each do |devices|
     volume = ec2.create_volume({size:  "#{node['ebs']['size']}",availability_zone:  "#{availability_zone}",volume_type: "gp2",})
        ec2.create_tags({resources: ["#{volume.volume_id}"],tags:[{key: "voltag",value:  "#{node['ebs']['voltag']}",},]})
        if volume.state == "creating"
            until ec2.describe_volumes({volume_ids: [volume.volume_id],}).volumes[0].state == "available" do
                            puts "Volume status:" + ec2.describe_volumes({volume_ids: [volume.volume_id],}).volumes[0].state
                            sleep 0.25
                 end
             end
        attachment = ec2.attach_volume({volume_id: "#{volume.volume_id}",instance_id: "#{instance}", device: "#{devices}",})
             until ec2.describe_volumes({volume_ids: [volume.volume_id],}).volumes[0].attachments[0].state == "attached" do
                     puts "Volume state is:" + ec2.describe_volumes({volume_ids: [volume.volume_id],}).volumes[0].attachments[0].state       
             end 
   # create a filesystem
   execute 'mkfs' do
      command "mkfs -t ext4 #{devices}"
   end
   directory "#{node['ebs']['mount_path']}" do
      owner 'root'
      group  'root'
      mode   '0755'
      action :create
   end
   mount "#{node['ebs']['mount_path']}" do
      device devices
      fstype 'ext4'
      options 'noatime,nobootwait'
      action [:enable, :mount]
       end
     end
   else
   
   # Volume found, lets attach it
   puts "Found" + ebs.volumes[0].volume_id
   node["ebs"]["device"].each do |devices|
      attachment = ec2.attach_volume({volume_id: "#{volume.volume_id}",instance_id: "#{instance}",device: "#{devices}",})
   
     until ec2.describe_volumes({volume_ids: [volume.volume_id],}).volumes[0].attachments[0].state == "attached" do
         puts "Volume state is:" + ec2.describe_volumes({volume_ids: [volume.volume_id],}).volumes[0].attachments[0].state
         end
     end
   end
