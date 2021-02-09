---
layout: post
title:  "Notes on AWS S3 Presigned URLs"
date:   2021-02-08 21:48:16 +0200
categories: aws presigned-urls s3
---

Recently I've been working on a project to further upgrade the security for the company that I work for.
This blog post will cover some of my learnings during this project. The examples will be in PHP, while I do have my 
opinion about PHP, it's the safest way for me to guarantee that my examples work :).

[comment]: <> (// guide will give an in depth description on how to setup presigned urls on your AWS S3 bucket. )

## A Little Background Story
Users directly upload pictures to our platform, during the upload process they are resized into two types of sizes, a thumbnail
size and a preview size. This yields 3 images that are stored on S3, each with saved with a long string of random characters into an
S3 bucket. Now, there is no way on earth someone could guess the names of these images, even given the fact that
we store an insane amount of images, our human brain cannot comprehend the size of the search space in which an attacker
has to go through to be very very lucky...

Now, that said, a fair remark I got on this was:

> *"But uhh, what if the paths to the s3 bucket objects were leaked? Somehow?".* 

I won't get into the details of this, but this is a valid remark because evil forces with the right access pass, will no doubly
be able to pull something off like this. So, in short, we need to block public access to our bucket. This can be done
by either using Signed or Presigned URLS.

[comment]: <> (- https://liveroomlk.medium.com/cloudfront-signed-urls-cookies-and-s3-presigned-urls-be850c34f9ce)
[comment]: <> (_ https://advancedweb.hu/how-to-solve-cors-problems-when-redirecting-to-s3-signed-urls/)

## What are Signed URLS?
For the Signed URLs mechanism, the backend application will generate URLS that are signed, using a private key for which Cloudfront
has the public key. The link generated will
point towards a CloudFront Distribution that is able to verify the signing hidden in the requests parameters. The benefit
is that you can use Cloudfront and take use of its caching mechanisms as well as protect the resources it has to. It does require root access to the AWS Account,
so depending on your situation, this may be more difficult.

> More will come 

## What are Pre-signed URLS?
AWS Pre-signed URLS allow for temporarily grant specific rights to someone with the link. This being, to **read**, **write** or **delete**
objects in S3. From a server side perspective, this could simply mean that we generate the Presigned URL on the server and that link to 
the client. The client can use the URLs to perform the desired operation, depending on the access right granted by the server.

A prerequisites is that the AWS Service needs to have access to the location to the 
Bucket and Path for which it is generating a Presigned URL. You can either use an AWS Key and AWS Secret, 
but it's far more secure and scalable solution to use an Iam Role that is attached to the AWS service of your backend entity in AWS.
To use it, you should use pass [Aws\CacheInterface](https://docs.aws.amazon.com/sdk-for-php/v3/developer-guide/guide_configuration.html), 
as the credentials so setup the`S3Client`. An example of this is shown in Listings 1.

This will prevent long reuse of an AWS Key and Secret, this reduces the risk of those keys being leaked in any way and be active forever without knowing. 
Role based access will give you full power in what is allowed by that specific role. Another benefit is that is a less expensive operation.

## The Goal
In the end, we want users to use a link to our backend server and get automatically redirected to S3 with a presigned url or signed url.
The choice for the current implementation has fallen on the Pre-signed urls. It requires one less entity in the scheme of things,
and we do not need the access to the AWS root account to create a key pair, so for our situation Presigned URLS were our best pick.

1. The user logs in to our platform
2. Retrieves resources and their attachments
3. The attachments have links directly leading to our Backend.
4. We check if they have a valid login and if they are allowed to see the current requested resource using their access key.

### AWS S3 Client Initialization
This documentation is a bit misleading on what you should supply as the credentials option for the S3Client:

**Copied from the AWS Docs on AWS S3 Client Credentials initialisation:**
> If you don’t provide a credentials option, the SDK attempts to load credentials from your environment in the following order:
>  1. Load credentials from environment variables.
>  1. Load credentials from a credentials .ini file.
>  1. Load credentials from an IAM role. 

But if yoo provide an object of type `Aws\CacheInterface`, you will get the AWS Key and Secret that the S3Client that is has gotten itself from the IAM Role. 
The AWS Key and Secret it has retrieved from the 
[EC2 Service Metadata](https://docs.amazonaws.cn/zh_cn/aws-sdk-php/guide/latest/guide/credentials.html#using-iam-roles-for-amazon-ec2-container-service-tasks)
, which is retrieved by means of a request. This is obviously slower than if were to store those keys temporarily which can be reused.

### Getting an S3 Object with a Presigned URL
Following the Example on the [AWS Documentation on PresignedURLs](https://docs.aws.amazon.com/AmazonS3/latest/dev/RetrieveObjSingleOpPHP.html),
and combining this the `Aws\CacheInterface`, we get the following
result for retrieving an object using the presigned URL. Note that this not the result we are aiming for yet... we don't want to
download the object in the Backend, we want to give the sweet task of the downloading the object to the client.

~~~php
<?php

/**
 * Use get and set to store your credentials in a Cache that can be quickly accessed.
 * 
* Class CacheObject
 */
class CacheObject implements Aws\CacheInterface {
    public function get($key) {}
    public function set($key, $value, $ttl = 0) {}
    public function remove($key) {}
}

... 

$keyName = 'uploads/aaaaaaaaaaaaaaaaaaaaa.jpg';

$credentials = new CacheObject();

$s3Client = new Aws\S3\S3Client([
  'version'     => 'latest',
  'region'      => 'eu-west-1',
  'credentials' => $credentials
]);

$cmd = $s3Client->getCommand('GetObject', [
    'Bucket' => 'derp-bucket',
    'Key' => $keyName,
]);

$request = $s3Client->createPresignedRequest($cmd, '+2 minutes');

~~~
> Listings 1: Shows an Example of how to get an S3 Object from S3 using a Pre-singed Request.

This is nice, but we don't want the actual file, we want the client to fetch it instead. We just need the URL and send
an HTTP Redirect so the client can follow that link instead.

### Getting a Presigned URL.
Now remember that the Goal is to redirect the user to the S3 Bucket, after we have checked their login. So we have
to generate the Presigned URL by the following snippet:

~~~php
$lifetime = 60;

$cmd = $s3->getCommand('GetObject', [
    'Bucket' => 'derp-bucket',
    'Key' => $keyName,
]);

$presignedUrlRequest = $this->S3->createPresignedRequest($cmd, DateUtils::time() + $lifetime);
$presignedUrl = (string)$presignedUrlRequest->getUri(); 

~~~
> Listings 2: Shows an Example of how to get the Pre-signed Url from S3.

An important part was to cast the result of the getUri function to a String. It returns an object that contains
a toString method. Not converting it will give you hours of fun debugging, you're welcome :).
~~~php
$presignedUrl = (string)$presignedUrlRequest->getUri();
~~~

### Sending the Redirect to the Client
Now that we have the URL we can send a 303 to with the location header set to the Presigned URL. The HTTP Client of
the user will automatically follow the redirect and start downloading the S3 Object. Now at this moment a problem arose.
This problem is discussed in the following Section.

#### The Authorization Header Problem
The `Authorization Header` is not usable now. You cannot use the Authorization Header to authenticate the user on your platform
AND send a redirect to AWS. Strangely enough, the Authorization Header is not stripped after a redirect, see [[1]](#references). That's something I never realized. 
And who would until they find out the hard way right?

Anyway, to prevent this, we go back to our old school Cookie Authorization. So instead of the Authorization Header that contains the acces key, they must use send 
a Cookie to Authorize themselves on our server to get access to S3 Object. A well known fact about Cookies is that they are automatically stripped if the domain changes. 

The following Error is given when trying to send the Authorization Header (unknowingly...).

~~~xml
<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>InvalidArgument</Code>
<Message>Only one auth mechanism allowed; only the X-Amz-Algorithm query parameter, Signature query string parameter or the Authorization header should be specified</Message>
<ArgumentName>Authorization</ArgumentName>
    <ArgumentValue>Bearer Token</ArgumentValue><RequestId>
</RequestId>
    <HostId>...</HostId>
</Error>
~~~
> Listings 3: Shows the error message received upon the HTTP Redirect where the Authorization Header was not stripped from the request.

In the Presigned URL the X-Amz-Algorithm contains

#### Fix the CORS problem
> Will come

# Conclusion
In these notes I've aimed to give an example of how Pre-signed Urls work and how they can be used in an production environment.
I've copied and put together some AWS Documentation to make small example of how Pre-signed Urls could
work for an application. We've seen an example of how to set up the S3 Client efficiently using the Cache Object, an example
that I haven't really seen on the AWS Documentation.

We've seen the problem that occur when using an HTTP Redirect Request, that it does not strip out the Authorization 
Header after Redirection. In my opinion HTTP Client should really strip those out to prevent any dangerous leakage
of Access Keys. The Authorization Header is the modern version of the Cookie Header, yet it is less secure considering this.

### References
#### 1. "How to remove authorization header in a http 302 response - Stack ...."
   [https://stackoverflow.com/questions/35400943/how-to-remove-authorization-header-in-a-http-302-response/45217599. Accessed 9 Feb. 2021.](https://stackoverflow.com/questions/35400943/how-to-remove-authorization-header-in-a-http-302-response/45217599. Accessed 9 Feb. 2021.)

[comment]: <> (// TODO: info on how a service in AWS gets a AWS Key and Secret granted by the platform during runtime)

