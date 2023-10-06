## Objectives
<br />A solution is needed in order to handle a lot of http requsts.

## Solution
![Image](https://github.com/huyphamch/terraform-aws-create-scalable-web-rds/blob/master/diagrams/AWS_architecture.drawio.png)
<br />Add Route53 to redirect domain name requests to load balancer.
<br />Add a load balancer to distribute requests to multiple EC2-instances via auto-scaling and ensure responsiveness of the website.
<br />Add auto-scaling to handle requests from the load balancer and dynamically increase/decrease EC2-instances based on CPU usage to support horizontal scalability.
<br />The EC2-instances are protected in the private subnet and can only be accessed by the load balancer.
<br />The EC2-instances have access to the internet via their own NAT-Gateway through the Internet Gateway in order to download installation packages like the web-server.
<br />The database protected in the private subnet and can only be accessed by the EC2-instances.
## Prerequisites
<br /> Build on top of code and results from [Project 1](https://github.com/huyphamch/terraform-aws-create-web-rds)

## Usage
<br /> 1. Open terminal
<br /> 2. Before you can execute the terraform script, your need to configure your aws environment first.
<br /> aws configure
<br /> AWS Access Key ID: See IAM > Security credentials > Access keys > Create access key
<br /> AWS Secret Access Key: See IAM > Security credentials > Access keys > Create access key
<br /> Default region name: us-east-1
<br /> Default output format: json
<br /> 3. Now you can apply the terraform changes.
<br /> terraform init
<br /> terraform apply --auto-approve
<br /> Note: Update the nameservers from Route53 record in the domain to redirect requests to AWS Route53 nameservers.
<br /> Result: Calling the URL from the web browser should display the static web page
<br /> 4. At the end you can cleanup the created AWS resources.
<br /> terraform destroy --auto-approve
