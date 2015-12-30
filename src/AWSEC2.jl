#==============================================================================#
# AWSEC2.jl
#
# EC2 API. See http://aws.amazon.com/documentation/ec2/
#
# Copyright Sam O'Connor 2015 - All rights reserved
#==============================================================================#


module AWSEC2

__precompile__()

export ec2, ec2_id, delete_ec2, create_ec2


using AWSCore
using SymDict
using Retry
include("mime.jl")


ec2(aws; args...) = ec2(aws, StringDict(args))


function ec2(aws, query)

    do_request(post_request(aws, "ec2", "2014-02-01", StringDict(query)))
end


function ec2_id(aws, name)

    r = ec2(aws, @SymDict(Action             = "DescribeTags",
                          "Filter.1.Name"    = "key",
                          "Filter.1.Value.1" = "Name",
                          "Filter.2.Name"    = "value",
                          "Filter.2.Value.1" = name))

    r = r["tagSet"]

    if r == ""
        throw(AWSException("InvalidInstanceID.NotFound",
                           "Instance ID not found for Name: $name", ""))
    end
    return r["item"]["resourceId"]
end


function delete_ec2(aws, name)

    ec2(aws, @SymDict(Action = "DeleteTags", 
                      "ResourceId.1" = ec2_id(aws, name),
                      "Tag.1.Key" = "Name"))

    ec2(aws, @SymDict(Action = "TerminateInstances", 
                      "InstanceId.1" = old_id))
end


function create_ec2(aws, name; ImageId="ami-1ecae776",
                               UserData="",
                               Policy="",
                               args...)

    if isa(UserData,Array)
        UserData=base64encode(mime_multipart(UserData))
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

        request[symbol("IamInstanceProfile.Name")] = name
    end

    r = nothing

    @repeat 4 try

        # Deploy instance...
        r = ec2(aws, request)

    catch e
        @delay_retry if e.code == "InvalidParameterValue" end
    end

    r = r["RunInstancesResponse"]["instancesSet"]["item"]

    ec2(aws, StringDict("Action"       => "CreateTags",
                        "ResourceId.1" => r["instanceId"],
                        "Tag.1.Key"    => "Name",
                        "Tag.1.Value"  => name))

    return r
end



end # module AWSEC2



#==============================================================================#
# End of file.
#==============================================================================#
