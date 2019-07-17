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
using SymDict
using Retry
using Base64


ec2(aws, action::String; args...) = ec2(aws, action, stringdict(args))

ec2(aws, args::AbstractDict) = ec2(aws, args["Action"], args)

ec2(aws::AWSConfig, action::String, args) = AWSCore.Services.ec2(aws, action, args)


function ec2_id(aws::AWSConfig, name)

    r = ec2(aws, "DescribeTags", @SymDict("Filter.1.Name"    = "key",
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

    ec2(aws, "DeleteTags", @SymDict("ResourceId.1" = id, "Tag.1.Key" = "Name"))
    ec2(aws, "TerminateInstances", @SymDict("InstanceId.1" = id))
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
        @ignore if ecode(e) == "TerminateInstances" end
    end

    request = @SymDict(ImageId,
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
            @ignore if ecode(e) == "EntityAlreadyExists" end
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
            @ignore if ecode(e) == "EntityAlreadyExists" end
        end


        @repeat 2 try 

            iam(aws, Action = "AddRoleToInstanceProfile",
                     InstanceProfileName = name,
                     RoleName = name)

        catch e
            @retry if ecode(e) == "LimitExceeded"
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
        r = ec2(aws, "RunInstances", request)

    catch e
        @delay_retry if ecode(e) == "InvalidParameterValue" end
    end

    r = r["instancesSet"]["item"]

    ec2(aws, "CreateTags", Dict("ResourceId.1" => r["instanceId"],
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
    ami = ec2(aws, "DescribeImages", @SymDict("Filter.1.Name" = "owner-alias",
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
