#==============================================================================#
# AWSEC2.jl
#
# EC2 API. See http://aws.amazon.com/documentation/ec2/
#
# Copyright OC Technology Pty Ltd 2015 - All rights reserved
#==============================================================================#


__precompile__()


module AWSEC2

export ec2, ec2_id, delete_ec2, create_ec2, ec2_bash


using AWSCore
using AWSIAM
using SymDict
using Retry


ec2(aws; args...) = ec2(aws, StringDict(args))


function ec2(aws::AWSConfig, query)

    do_request(post_request(aws, "ec2", "2014-02-01", StringDict(query)))
end


function ec2_id(aws::AWSConfig, name)

    r = ec2(aws, @SymDict(Action             = "DescribeTags",
                          "Filter.1.Name"    = "key",
                          "Filter.1.Value.1" = "Name",
                          "Filter.2.Name"    = "value",
                          "Filter.2.Value.1" = name))

    r = r["tagSet"]

    if r == ""
        return nothing
    end
    return r["item"]["resourceId"]
end


function delete_ec2(aws::AWSConfig, name)

    id = ec2_id(aws, name)

    if id == nothing
        return
    end

    ec2(aws, @SymDict(Action = "DeleteTags", 
                      "ResourceId.1" = id,
                      "Tag.1.Key" = "Name"))

    ec2(aws, @SymDict(Action = "TerminateInstances", 
                      "InstanceId.1" = id))
end


function create_ec2(aws::AWSConfig, name; ImageId="ami-1ecae776",
                                          UserData="",
                                          Policy="",
                                          args...)

    if isa(UserData,Array)
        UserData=base64encode(AWSCore.mime_multipart(UserData))
    end

    # Delete old instance...
    @protected try 

        delete_ec2(aws, name)

    catch e
        @ignore if e.code == "TerminateInstances" end
    end

    request = @SymDict(Action="RunInstances",
                       ImageId,
                       UserData,
                       MinCount="1",
                       MaxCount="1",
                       args...)

    # Set up InstanceProfile Policy...
    if Policy != ""

        @protected try 

            iam(aws, Action = "CreateRole",
                     Path = "/",
                     RoleName = name,
                     AssumeRolePolicyDocument = """{
                        "Version": "2012-10-17",
                        "Statement": [ {
                            "Effect": "Allow",
                            "Principal": {
                                "Service": "ec2.amazonaws.com"
                            },
                            "Action": "sts:AssumeRole"
                        } ]
                     }""")

        catch e
            @ignore if e.code == "EntityAlreadyExists" end
        end

        iam(aws, Action = "PutRolePolicy",
                 RoleName = name,
                 PolicyName = name,
                 PolicyDocument = Policy)

        @protected try 

            iam(aws, Action = "CreateInstanceProfile",
                     InstanceProfileName = name,
                     Path = "/")
        catch e
            @ignore if e.code == "EntityAlreadyExists" end
        end


        @repeat 2 try 

            iam(aws, Action = "AddRoleToInstanceProfile",
                     InstanceProfileName = name,
                     RoleName = name)

        catch e
            @retry if e.code == "LimitExceeded"
                iam(aws, Action = "RemoveRoleFromInstanceProfile",
                         InstanceProfileName = name,
                         RoleName = name)
            end
        end

        request[Symbol("IamInstanceProfile.Name")] = name
    end

    r = nothing

    @repeat 4 try

        # Deploy instance...
        r = ec2(aws, request)

    catch e
        @delay_retry if e.code == "InvalidParameterValue" end
    end

    r = r["instancesSet"]["item"]

    ec2(aws, Dict("Action"       => "CreateTags",
                  "ResourceId.1" => r["instanceId"],
                  "Tag.1.Key"    => "Name",
                  "Tag.1.Value"  => name))

    return r
end


function ec2_bash(aws::AWSConfig, script...;
                  instance_name = "ec2_bash",
                  instance_type = "c3.large",
                  image = "amzn-ami-hvm-2015.09.1.x86_64-gp2",
                  ssh_key = nothing,
                  policy = nothing,
                  packages = [])

    user_data = [(

        "cloud_config.txt", "text/cloud-config",

        "packages:\n$(join([" - $p\n" for p in packages]))"

    ),(

        "ec2_bash.sh", "text/x-shellscript",

        """#!/bin/bash

        set -x
        set -e

        $(join(script, "\n"))

        shutdown -h now
        """
    )]

    # http://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html
    ami = ec2(aws, @SymDict(
            Action = "DescribeImages",
            "Filter.1.Name" = "owner-alias",
            "Filter.1.Value" = "amazon",
            "Filter.2.Name" = "name",
            "Filter.2.Value" = image))

    request = @SymDict(ImageId = ami["imagesSet"]["item"]["imageId"],
                       InstanceType = instance_type,
                       UserData = user_data)
    if ssh_key != nothing
        request[:KeyName] = ssh_key
    end
    if policy != nothing
        request[:Policy] = policy
    end

    create_ec2(aws, instance_name; request...)
end

end # module AWSEC2



#==============================================================================#
# End of file.
#==============================================================================#
