# AWSEC2

AWS EC2 Interface for Julia

```julia
using AWSEC2

aws = AWSCore.aws_config()

policy = """{
    "Version": "2012-10-17",
    "Statement": [ {
        "Effect": "Allow",
        "Action": [ "s3:PutObject", "s3:GetObject" ],
        "Resource": "arn:aws:s3:::my_bucket/*"
    } ]
}"""

init_data = [(

    "cloud_config.txt", "text/cloud-config",

    """packages:
     - git
     - gcc
    """

),(

    "build_julia.sh", "text/x-shellscript",

    """#!/bin/bash

    s3 cp s3://my_bucket/my_code.tgz /tmp
    tar xzf /tmp/my_code.tgz
    """
)]

create_ec2(aws, "my_server",
                ImageId      = "ami-1ecae776",
                InstanceType = "c3.large",
                KeyName      = "ssh-ec2",
                Policy       = policy,
                UserData     = init_data)

println("Instance Id: $(ec2_id(aws, "my_server))")

delete_ec2(aws, "my_server")


r = ec2(aws, Dict("Action"           => "DescribeImages",
                  "Filter.1.Name"    => "image-id",
                  "Filter.1.Value.1" => "ami-1ecae776"))
println(r)
```
