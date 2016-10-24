#==============================================================================#
# EC2/test/runtests.jl
#
# Copyright OC Technology Pty Ltd 2014 - All rights reserved
#==============================================================================#


using AWSEC2
using Base.Test

AWSCore.set_debug_level(1)


#-------------------------------------------------------------------------------
# Load credentials...
#-------------------------------------------------------------------------------

aws = AWSCore.aws_config()



#-------------------------------------------------------------------------------
# EC2 tests
#-------------------------------------------------------------------------------

@test ec2_id(aws, "Not a real server name!!") == nothing


r = ec2(aws, Dict("Action" => "DescribeImages",
                  "Filter.1.Name" => "owner-alias",
                  "Filter.1.Value" => "amazon",
                  "Filter.2.Name" => "name",
                  "Filter.2.Value" => "amzn-ami-hvm-2015.09.1.x86_64-gp2"))

@test r["imagesSet"]["item"]["description"] == 
      "Amazon Linux AMI 2015.09.1 x86_64 HVM GP2"



#==============================================================================#
# End of file.
#==============================================================================#
