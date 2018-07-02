[![Build Status](https://api.travis-ci.com/base2Services/ciinabox-ecs.svg?branch=develop)](https://api.travis-ci.com/base2Services/ciinabox-ecs.svg?branch=develop)


# ciinabox ECS

ciinabox pronounced ciin a box is a set of automation for building
and managing a bunch of CI tools in AWS using the Elastic Container Service (ECS).

Right Now ciinabox supports deploying:

 * [jenkins](https://jenkins.io/)
 * [drone](http://docs.drone.io)
 * [bitbucket](https://www.atlassian.com/software/bitbucket)
 * [hawtio](http://hawt.io/)
 * [nexus](http://www.sonatype.org/nexus/)
 * [artifactory](https://jfrog.com/open-source/)
 * plus custom tasks and stacks

## Setup

requires ruby 2.3+

install [ciinabox-ecs](https://rubygems.org/gems/ciinabox-ecs/) gem

```bash
$ gem install ciinabox-ecs
...
Done installing documentation for ciinabox-ecs after xx seconds
1 gem installed

$ ciinabox-ecs help
Usage: ciinabox-ecs action1 action2 action3 ciinabox_name
Valid actions:
name                 |description         

active               |Switch active ciinabox
create               |Creates the ciinabox environment
create_server_cert   |Create self-signed SSL certs for use with ciinabox
create_source_bucket |Creates the source bucket for deploying ciinabox
deploy               |Deploy Cloudformation templates to S3
down                 |Turn off your ciinabox environment
full_install         |Initialize configuration, create required assets in AWS account, create Cloud Formation stack
generate             |Generate CloudFormation templates
generate_keypair     |Generate ciinabox AWS keypair
init                 |Initialise a new ciinabox environment
package_lambdas      |Package Lambda Functions as ZipFiles
ssh                  |SSH into your ciinabox environment
status               |Current status of the active ciinabox
tear_down            |Deletes/tears down the ciinabox environment
up                   |Turn on your ciinabox environment
update               |Updates the ciinabox environment
update_cert_to_acm   |Replace previously auto-generated IAM certificate with auto-validated ACM certificate (if one exists)
upload_server_cert   |Uploads SSL server certs for ciinabox
watch                |Monitors status of the active ciinabox until failed or successful

```

If setting your own parameters and additional services, they should be configured as such:

#### User-defined parameters:
ciinaboxes/ciinabox_name/config/params.yml

e.g:
```yaml
log_level: ':debug'
timezone: 'Australia/Melbourne'
```

#### User-defined services:
If you wish to add additional containers to your ciinabox environment, you can specify them like so:
ciinaboxes/ciinabox_name/config/services.yml

e.g:

```yaml
    services:
      - jenkins:
      - bitbucket:
          LoadBalancerPort: 22
          InstancePort: 7999
          Protocol: TCP
      - hawtio:
      - nexus:
      - artifactory:
      - drone:
```

Please note that if you wish to do this, that you also need to create a CFNDSL template for the service under templates/services, with the name of the service as the filename (e.g. bitbucket.rb)

## Getting Started

To get started install `ciinabox-ecs` ruby gem

```bash
$ gem install ciinabox-ecs
```

During the setup process, you'll need to provide domain for the tools (e.g. `*.tools.example.com`) that has
matching Route53 zone in same AWS account where you are creating ciinabox. Optionally you can use local hosts file
hack in order to get routing working, but in this case usage of ACM certificates is not an option, and you'll need
to use selfsigned IAM server certificates.

### Quick setup

You can be guided through full installation of ciinabox by running `full_install` action. Interactive
command line prompt will offer you defaults for most of required options.

```bash
$ ciinabox-ecs full_install

```

### Step by step setup

1. Initialize/Create a new ciinabox environment. Please note that any user-defined services and parameters will be merged during this task into the default templates
  ```bash
  $ ciinabox-ecs init
  Enter the name of ypur ciinabox:
  myciinabox
  Enter the id of your aws account you wish to use with ciinabox
  111111111111
  Enter the AWS region to create your ciinabox (e.g: ap-southeast-2):
  us-west-2
  Enter the name of the S3 bucket to deploy ciinabox to:
  source.myciinabox.com
  Enter top level domain (e.g tools.example.com), must exist in Route53 in the same AWS account:
  myciinabox.com
  # Enable active ciinabox by executing or override ciinaboxes base directory:
  export CIINABOXES_DIR="ciinaboxes/"
  export CIINABOX="myciinabox"
  ```
  You can override the default ciinaboxes directory by setting the CIINABOXES_DIR environment variable. Also the DNS domain you entered about must already exist in Route53


3. Generate self-signed wild-card cert for your ciinabox
  ```bash
  $ ciinabox-ecs create_server_cert [ciinabox_name]
  Generating a 4096 bit RSA private key
  .......................................................................................................................................++
  ....................++
  writing new private key to 'ciinaboxes/myciinabox/ssl/ciinabox.key'
  -----
  ```

4. Create IAM server-certificates
  ```bash
  $ ciinabox-ecs upload_server_cert [ciinabox_name]
  Successfully uploaded server-certificates
  ```

5. Create ciinabox S3 source deployment bucket
  ```bash
  $ ciinabox-ecs create_source_bucket [ciinabox_name]
  Successfully created S3 source deployment bucket source.myciinabox.com
  ```

6. Create ssh ec2 keypair
  ```bash
  $ ciinabox-ecs generate_keypair [ciinabox_name]
  Successfully created ciinabox ssh keypair
  ```

7. Generate ciinabox cloudformation templates
  ```bash
  $ ciinabox-ecs generate [ciinabox_name]
  Writing to output/ciinabox.json
  using extras [[:yaml, "ciinaboxes/myciinabox/config/default_params.yml"], [:yaml, "config/services.yml"], [:ruby, "ext/helper.rb"]]
  Loading YAML file ciinaboxes/myciinabox/config/default_params.yml
  Setting local variable ciinabox_version to 0.1
  Setting local variable ciinabox_name to myciinabox
  ......
  ......
  $ ls -al output/
  total 72
  drwxr-xr-x   9 ciinabox  staff    306  9 Sep 21:52 .
  drwxr-xr-x  14 ciinabox  staff    476 19 Oct 10:26 ..
  -rw-r--r--   1 ciinabox  staff      0  7 Sep 14:30 .gitkeep
  -rw-r--r--   1 ciinabox  staff   1856 19 Oct 13:27 ciinabox.json
  -rw-r--r--   1 ciinabox  staff   6096 19 Oct 13:27 ecs-cluster.json
  -rw-r--r--   1 ciinabox  staff   1358  9 Sep 17:39 ecs-service-elbs.json
  -rw-r--r--   1 ciinabox  staff   3250 19 Oct 13:27 ecs-services.json
  drwxr-xr-x   4 ciinabox  staff    136  9 Sep 21:53 services
  -rw-r--r--   1 ciinabox  staff  13218 19 Oct 13:27 vpc.json
  ```
  This will render the cloudformation templates locally in the output directory

8. Deploy/upload cloudformation templates to source deployment bucket
  ```bash
  $ ciinabox-ecs deploy [ciinabox_name]
  upload: output/vpc.json to s3://source.myciinabox.com/ciinabox/0.1/vpc.json
  upload: output/ecs-services.json to s3://source.myciinabox.com/ciinabox/0.1/ecs-services.json
  upload: output/ciinabox.json to s3://source.myciinabox.com/ciinabox/0.1/ciinabox.json
  upload: output/services/jenkins.json to s3://source.myciinabox.com/ciinabox/0.1/services/jenkins.json
  upload: output/ecs-service-elbs.json to s3://source.myciinabox.com/ciinabox/0.1/ecs-service-elbs.json
  upload: output/ecs-cluster.json to s3://source.myciinabox.com/ciinabox/0.1/ecs-cluster.json
  Successfully uploaded rendered templates to S3 bucket source.myciinabox.com
  ```

9. Create/Lanuch ciinabox environment
  ```bash
  $ ciinabox-ecs create base2
  Starting updating of ciinabox environment
  # checking status using
  $ ciinabox-ecs status base2
  base2 ciinabox is in state: CREATE_IN_PROGRESS
  # When your ciinabox environment is ready the status will be
  base2 ciinabox is alive!!!!
  ECS cluster private ip:10.xx.xx.xx
  ```
  You can access jenkins using http://jenkins.myciinabox.com

## Additional Tasks

### ciinabox-ecs update

Runs a cloudformation update on the current ciinabox environment. You can use this task if you've modified the default_params.yml config file for your ciinabox and you want to apply these changes to your ciinabox.

A common update would be to lock down ip access to your ciinabox environment

1. edit ciinaboxes/myciinabox/config/default_params.yml

  ```yaml
  ....
  #Environment Access
  #add list of public IP addresses you want to access the environment from
  #default to public access probably best to change this
  opsAccess:
    - my-public-ip
    - my-my-other-ip
  #add list of public IP addresses for your developers to access the environment
  #default to public access probably best to change this
  devAccess:
    - my-dev-teams-ip
  ....
  ```

2. update your ciinabox
  ```bash
  $ ciinabox-ecs generate deploy update [ciinabox_name]
  $ ciinabox-ecs status [ciinabox_name]
  ```

### ciinabox-ecs tear_down [ciinabox_name]

Tears down your ciinabox environment. But why would you want to :)


### ciinabox-ecs up [ciinabox_name]

Relies on [cfn_manage](https://rubygems.org/gems/cfn_manage) gem to bring stack up. Stack needs to be stopped using `ciinabox:down` task

### ciinabox-ecs down [ciinabox_name]

Relies on [cfn_manage](https://rubygems.org/gems/cfn_manage) gem to stop the stack. Will set ASG size to 0 (and optionally set bastion ASG size to 0).

## Adding Custom Templates per ciinabox

Custom templates should be defined under <CIINABOXES_DIR>/<CIINABOX>/templates.

For each stack that needs to be included add a stack under extra_stacks in the config.yml.  

By default the name of the nested stack will be assumed to be the file name when the template is getting called.  This can be overriden.  

Parameters get passed in as a hash and all get passed in from the top level.

\#extra_stacks:
\#  elk:
\#    #define template name? - optional
\#    file_name: elk
\#    parameters:
\#      RoleName: search
\#      CertName: x

# Extra configs

## To restore the volume from a snapshot in an existing ciinabox update the following 2 values

ecs_data_volume_snapshot: (Note: if ciinabox exists this is two step approach you will need to change volume name and change back volume name)

ecs_data_volume_name: override this if you need to re-generate the volume, e.g. from snapshot

\#add if you want ecs docker volume != 22GB - must be > 22

\#ecs_docker_volume_size: 100

\#use this to change volume snapshot for running ciinabox

\#ecs_data_volume_name: "ECSDataVolume2s"

\#set the snapshot to restore from

\#ecs_data_volume_snapshot: snap-49e2b3b5

\#set the size of the ecs data volume -- NOTE: would take a new volume - i.e. change volume name

\#ecs_data_volume_size: 250

\#optional ciinabox name if you need more than one or you want a different name

\#stack_name: ciinabox-tools

## For internal elb for jenkins

```
internal_elb: false

 - jenkins:
    LoadBalancerPort: 50000
    InstancePort: 50000
    Protocol: TCP
# needs internal_elb: true
```

## Nginx Reverse Proxy Config

If you need to pass in extra nginx configuration such as `client_max_body_size 100m;` to the proxy you can by adding the following text block to you params.yaml

```yaml
proxy_config: |
  server_tokens off;
  client_max_body_size 100m;
```

# Ciinabox configuration

## Bastion (Jumpbox) instance

If you have need to access ECS Cluster instance running Jenkins server via secure shell, you may do so by logging
into bastion host first. By default, bastion is disabled for ciinabox Cloud Formation stack, however you can enable
it by using `bastion_stack` configuration key. Bastion will be launched as part of AutoScaling Group of size 1,
allowing it to self heal in case of system or instance check failure.

```yaml
include_bastion_stack: true
```

It is also possible to override other bastion host parameters, such as Amazon Machine Image and instance type
used for Launch Configuration. Defaults are below

```yaml
bastionInstanceType: t2.micro
# Amazon Linux 2017.09
bastionAMI:
  us-east-1:
   ami: ami-c5062ba0
  us-east-2:
   ami: ami-c5062ba0
  us-west-2:
   ami: ami-e689729e
  us-west-1:
   ami: ami-02eada62
  ap-southeast-1:
   ami: ami-0797ea64
  ap-southeast-2:
   ami: ami-8536d6e7
  eu-west-1:
   ami: ami-acd005d5
  eu-west-2:
   ami: ami-1a7f6d7e
  eu-central-1:
   ami: ami-c7ee5ca8

```

## Vpn (OpenVpn) instance

You can create a openvpn access server instance complete by using the bellow config. It will create a new ecs cluster in the public subnet and launch [base2/openvpn-as](https://hub.docker.com/r/base2/openvpn-as/) container. It mounts a data volume to persist all configuration and logs in `/data`. Uses the existing `ecs_ami` as the underlying instance ami.

```yaml
include_vpn_stack: true
```

It is also possible to override the vpn instance type used for Launch Configuration. Defaults are below

```yaml
vpnInstanceType: t2.small
```

## IAM Roles

Default IAM permission for ciinabox stack running Jenkins server are set in `config/default_params.yml`, under
`ecs_iam_role_permissions_default` configuration key. You can extend this permissions on a ciinabox level
using `ecs_iam_role_permissions_extras` key. E.g.

(within `$CIINABOXES_DIR/$CIINABOX/config/params.yml`)
```yaml

ecs_iam_role_permissions_extras:
  -
    name: allow-bucket-policy
    actions:
      - s3:PutBucketPolicy

```

## Allowing connections from NAT gateway

If ECS Cluster and running Jenkins will try to access itself via public route and url, you will need
to allow such traffic using Security Group rules. As NAT Gateway is used for sending all requests to internet,
it is NAT Gateways IP address that should be added to Group rules. Use `allow_nat_connections` configuration
key for this.

```yaml
allow_nat_connections: false
```

## Automatic issuance and validation of ACM SSL certificate

This setting is enabled by default in default parameters. During the ciinabox init stage, you will be
asked if you want to utilise this functionality. Essentially, custom cloudformation resource based on
python [aws-acm-validator](https://pypi.python.org/pypi/aws-acm-cert-validator) python package will
request and validate ACM certificate through appropriate Route 53 DNS validation record.

### To disable during ciinabox setup

Answer question below with 'y' during ciinabox init stage

```text
Use selfsigned rather than ACM issued and validated certificate (y/n)? [n]
```

### To disable for existing ciinaboxes

Within `$CIINABOXES_DIR/$CIINABOX/params.yml`

```yaml
acm_auto_issue_validate: false
```

### To migrate previous versions of ciinabox to this functionality

After updating to latest ciinabox version including this functionality, you may want to update value of `default_ssl_cert_id`
configuration key to ARN of the freshly issued ACM certificate. You can do that using `update_cert_to_acm` action

```yaml
$ ciinabox-ecs update_cert_to_acm [ciinabox_name]
Set arn:aws:acm:ap-southeast-2:123456789012:certificate/2f2f3f9f-aaaa-bbbb-cccc-11dac04e7fb9 as default_cert_arn
```

## Enabling specific services

### Artifactory

Just add artifactory in your `ciinabox_name/config/services.yml`
Artifactory service is routed through nginx reverse proxy, so it's not
added to ELB by default (InstancePort=0)

```yaml
services:
 - artifactory:
```

Defaults for artifactory are stated below, so if need be they can be overridden

```yaml
services:
  - artifactory:
      ContainerImage: base2/ciinabox-artifactory:5.9.3
      ContainerMemory: 768
      ContainerCPU: 0
      InstancePort: 0
```

### Drone


Note the drone service requires a minimum yaml configuration of below
```yml
services:
  - drone:
      params:
        -
          VPC:
            Ref: VPC
        -
          SubnetPublicA:
            Ref: SubnetPublicA
        -
          SubnetPublicB:
            Ref: SubnetPublicB
        -
          ECSSubnetPrivateA:
            Ref: ECSSubnetPrivateA
        -
          ECSSubnetPrivateB:
            Ref: ECSSubnetPrivateB
        -
          SecurityGroupBackplane:
            Ref: SecurityGroupBackplane
        -
          SecurityGroupOps:
            Ref: SecurityGroupOps
        -
          SecurityGroupDev:
            Ref: SecurityGroupDev
        -
          SecurityGroupNatGateway:
            Ref: SecurityGroupNatGateway
        -
          SecurityGroupWebHooks:
            Ref: SecurityGroupWebHooks
        -
          ECSENIPrivateIpAddress:
            Ref: ECSENIPrivateIpAddress
      tasks:
        drone-server:
          env:
            DRONE_OPEN: true
```
to further configure drone ci refer to the drone ci's environment variable in the documentation http://docs.drone.io/installation/, you can add/override drone's environment variable to their corresponding yaml section (`drone-server` and `drone-agent`), example
```yml
      tasks:
        drone-server:
          env:
            DRONE_OPEN: true
            DRONE_SECRET: base2services # if this value is not specified, a secure random hex will be used
        drone-agent:
          env:
            DRONE_SECRET: base2services # if this value is not specified, a secure random hex will be used
```
