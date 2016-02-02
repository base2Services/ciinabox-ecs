# ciinabox ECS

ciinabox (CI in a Box) pronounced ciin a box is a set of automation for building
and managing a bunch of CI tools in AWS using the Elastic Container Service (ECS).

Right Now ciinabox supports deploying:

 * jenkins
 * private docker registry
 * chef server

## Setup

requires ruby 2.1+

1. git clone https://github.com/base2Services/ciinabox-ecs.git
2. cd ciinabox-ecs
3. bundle install
4. rake -T

## Getting Started

1. Initialize/Create a new ciinabox environment
  ```bash
  $ rake ciinabox:init
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
  # or run
  eval $(rake ciinabox:active[myciinabox])
  ```
  You can override the default ciinaboxes directory by setting the CIINABOXES_DIR environment variable. Also the DNS domain you entered about must already exist in Route53

2. check that your new ciinabox is the current active one
  ```bash
  $ rake ciinabox:active
  # Enable active ciinabox by executing or override ciinaboxes base directory:
  export CIINABOXES_DIR="ciinaboxes/"
  export CIINABOX="myciinabox"
  # or run
  eval $(rake ciinabox:active[myciinabox])
  ```

3. Generate self-signed wild-card cert for your ciinabox
  ```bash
  $ rake ciinabox:create_server_cert
  Generating a 4096 bit RSA private key
  .......................................................................................................................................++
  ....................++
  writing new private key to 'ciinaboxes/myciinabox/ssl/ciinabox.key'
  -----
  ```

4. Create IAM server-certificates
  ```bash
  $ rake ciinabox:upload_server_cert
  Successfully uploaded server-certificates
  ```

5. Create ciinabox S3 source deployment bucket
  ```bash
  $ rake ciinabox:create_source_bucket
  Successfully created S3 source deployment bucket source.myciinabox.com
  ```

6. Create ssh ec2 keypair
  ```bash
  $ rake ciinabox:generate_keypair
  Successfully created ciinabox ssh keypair
  ```

7. Generate ciinabox cloudformation templates
  ```bash
  $ rake ciinabox:generate
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
  $ rake ciinabox:deploy
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
  $ rake ciinabox:create
  Starting updating of ciinabox environment
  # checking status using
  $ rake ciinabox:status
  base2 ciinabox is in state: CREATE_IN_PROGRESS
  # When your ciinabox environment is ready the status will be
  base2 ciinabox is alive!!!!
  ECS cluster private ip:10.xx.xx.xx
  ```
  You can access jenkins using http://jenkins.myciinabox.com

## Additional Tasks

### ciinabox:update

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
  $ rake ciinabox:generate
  $ rake ciinabox:deploy
  $ rake ciinabox:update
  $ rake ciinabox:status  
  ```

### ciinabox:tear_down

Tears down your ciinabox environment. But why would you want to :)

### ciinabox:active[ciinabox]

Displays the current active ciinabox environment and allows you to change to a different one

### ciinabox:up

Not Yet implemented...pull-request welcome

### ciinabox:down

Not Yet implemented...pull-request welcome

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
