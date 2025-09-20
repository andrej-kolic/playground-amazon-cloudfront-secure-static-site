# Amazon CloudFront Secure Static Website

Use this solution to create a secure static website for your registered domain name. With this solution, your website:

- Is hosted on [Amazon S3](https://aws.amazon.com/s3/)
- Is distributed by [Amazon CloudFront](https://aws.amazon.com/cloudfront/)
- Uses an SSL/TLS certificate from [AWS Certificate Manager (ACM)](https://aws.amazon.com/certificate-manager/)
- Uses [CloudFront Response Header Policies](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-response-headers.html) to add security headers to every server response
- Is deployed with [AWS CloudFormation](https://aws.amazon.com/cloudformation/)

For more information about each of these components, see the **Solution details** section on this page.

## Solution overview

The following diagram shows an overview of how the solution works:

![Architecture](./docs/images/cf-secure-static-site-architecture.png)

1. The viewer requests the website at www.example.com.
2. If the requested object is cached, CloudFront returns the object from its cache to the viewer.
3. If the object is not in CloudFront’s cache, CloudFront requests the object from the origin (an S3 bucket).
4. S3 returns the object to CloudFront
5. CloudFront caches the object.
6. The object is returned to the viewer. Subsequent responses for the object are served from the CloudFront cache.

## Solution details

### S3 configuration

This solution creates an S3 bucket that hosts your static website’s assets. The website is only accessible via CloudFront, not directly from S3.

### CloudFront configuration

This solution creates a CloudFront distribution to serve your website to viewers. The distribution is configured with a CloudFront [origin access control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html) to make sure that the website is only accessible via CloudFront, not directly from S3. The distribution is also configured with a [CloudFront Response Header Policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-response-headers.html) that adds security headers to every response.

### ACM configuration

This solution creates an SSL/TLS certificate in ACM, and attaches it to the CloudFront distribution. This enables the distribution to serve your domain’s website using HTTPS.

### CloudFront Response Header Policy

The CloudFront Response Header Policy adds security headers to every response served by CloudFront.

The security headers can help mitigate some attacks, as explained in the [Amazon CloudFront - Understanding response header policies documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/understanding-response-headers-policies.html#understanding-response-headers-policies-security). Security headers are a group of headers in the web server response that tell web browsers to take extra security precautions. This solution adds the following headers to each response:

- [Strict-Transport-Security](https://infosec.mozilla.org/guidelines/web_security#http-strict-transport-security)
- [Content-Security-Policy](https://infosec.mozilla.org/guidelines/web_security#content-security-policy)
- [X-Content-Type-Options](https://infosec.mozilla.org/guidelines/web_security#x-content-type-options)
- [X-Frame-Options](https://infosec.mozilla.org/guidelines/web_security#x-frame-options)
- [X-XSS-Protection](https://infosec.mozilla.org/guidelines/web_security#x-xss-protection)
- [Referrer-Policy](https://infosec.mozilla.org/guidelines/web_security#referrer-policy)

For more information, see [Mozilla’s web security guidelines](https://infosec.mozilla.org/guidelines/web_security).

## Prerequisites

You must have a registered domain name, such as example.com, and point it to a Route 53 hosted zone in the same AWS account in which you deploy this solution. For more information, see [Configuring Amazon Route 53 as your DNS service](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring.html).

You can use `scripts/misc/create-hosted-zone.sh` to create Hosted Zone.

## Deploy the solution

> ⚠️ This template can only be deployed in the `us-east-1` region

To deploy the solution, you can use several methods:

1. **GitHub Actions with OIDC (Recommended)** - Secure automated deployment
2. **AWS CLI** - Command line deployment
3. **AWS CloudFormation Console** - Manual deployment through AWS Console  

> **Note:** You must have IAM permissions to launch CloudFormation templates that create IAM roles, and to create all the AWS resources in the solution. Also, you are responsible for the cost of the AWS services used while running this solution. For more information about costs, see the pricing pages for each AWS service.

### Method 1: GitHub Actions with OIDC (Recommended)

This method uses OpenID Connect (OIDC) for secure authentication without storing long-lived AWS credentials in GitHub.

**Prerequisites:**
- Forked repository with GitHub Actions enabled
- AWS CLI configured with admin permissions for initial setup

**Setup Steps:**

1. **Configure the deployment settings** in `deploy-config.json`:
    ```json
    {
       "name": "your-project-name",
       "region": "us-east-1",
       "oidc": {
          "oidc_arn": "",
          "github_org": "your-github-username",
          "github_repo": "your-repo-name"
       },
       "environments": {
          "dev": {
             "parameters": {
                "DomainName": "example.com",
                "SubDomain": "dev",
                "HostedZoneId": "Z1234567890ABC",
                "CreateApex": "no"
             }
          },
          "staging": {
             "parameters": {
                "DomainName": "example.com",
                "SubDomain": "staging",
                "HostedZoneId": "Z1234567890ABC",
                "CreateApex": "no"
             }
          },
          "prod": {
             "parameters": {
                "DomainName": "example.com",
                "SubDomain": "prod",
                "HostedZoneId": "Z1234567890ABC",
                "CreateApex": "yes"
             }
          }
       }
    }
    ```

2. **One-time OIDC Setup**:
   - Go to GitHub Actions in your repository
   - Run the "Setup GitHub OIDC Provider" workflow
   - Check the confirmation box and run the workflow
   - Copy the outputted Role ARN and add it as repository secret `AWS_ROLE_ARN`
   - Remove any existing AWS access key secrets (no longer needed)

   Alternatively, you can run locally:
   ```bash
   ./scripts/oidc.sh
   ```

3. **Deploy via GitHub Actions**: 
   - Use the "Deploy Static Website" workflow
   - Select environment (dev/staging/prod) and action (infra/content)
   - Or push to trigger automatic deployment

For detailed OIDC setup instructions, see [docs/OIDC_SETUP.md](docs/OIDC_SETUP.md).

### Method 2: Deploy using local shell scripts

This method uses the included deployment scripts to deploy the solution directly from your local machine.

**Prerequisites:**
- AWS CLI configured with appropriate permissions
- `jq` utility installed for JSON parsing
- `make` utility available

**Setup Steps:**

1. **Clone or download this repository**:
   ```bash
   git clone https://github.com/awslabs/aws-cloudformation-templates.git
   cd aws-cloudformation-templates/Solutions/CloudFrontSecureStaticSite
   ```

2. **Configure deployment settings** in `deploy-config.json`:
   ```json
   {
     "name": "your-project-name",
     "region": "us-east-1",
     "oidc": {
       "oidc_arn": "",
       "github_org": "your-github-username",
       "github_repo": "your-repo-name"
     },
     "environments": {
       "dev": {
         "parameters": {
           "DomainName": "example.com",
           "SubDomain": "dev",
           "HostedZoneId": "Z1234567890ABC",
           "CreateApex": "no"
         }
       },
       "prod": {
         "parameters": {
           "DomainName": "example.com",
           "SubDomain": "www",
           "HostedZoneId": "Z1234567890ABC",
           "CreateApex": "yes"
         }
       }
     }
   }
   ```

3. **Deploy the infrastructure**:
   ```bash
   # Deploy to development environment
   ./scripts/deploy.sh infra dev
   
   # Deploy to production environment
   ./scripts/deploy.sh infra prod
   ```

4. **Deploy your website content**:
   ```bash
   # First, add your content to the www/ directory
   # Then sync content to S3 and invalidate CloudFront cache
   ./scripts/deploy.sh content dev
   ```

**Available script commands:**

- `./scripts/deploy.sh help` - Display usage information
- `./scripts/deploy.sh validate` - Validate CloudFormation templates
- `./scripts/deploy.sh infra [env]` - Deploy infrastructure (CloudFormation stacks)
- `./scripts/deploy.sh content [env]` - Deploy website content and invalidate cache
- `./scripts/deploy.sh outputs [env]` - Display stack outputs (URLs, bucket names, etc.)

**Script workflow:**

The `infra` action will:
1. Package the static site content using `make package-static`
2. Create an S3 bucket for CloudFormation artifacts
3. Package CloudFormation templates with nested stacks
4. Deploy the complete infrastructure stack

The `content` action will:
1. Sync files from `www/` directory to the S3 bucket
2. Create a CloudFront cache invalidation to refresh content

**Example deployment workflow:**
```bash
# Validate templates first
./scripts/deploy.sh validate

# Deploy infrastructure
./scripts/deploy.sh infra dev

# View stack information
./scripts/deploy.sh outputs dev

# Update content
# (Make changes to files in www/ directory)
./scripts/deploy.sh content dev
```

### Method 3: Use the CloudFormation console

**To deploy the solution using the CloudFormation console**

1. Click the **Launch on AWS** button to open the solution in the CloudFormation console.

   [![Launch the Amazon CloudFront secure static website with CloudFormation](./docs/images/deploy-to-aws.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=amazon-cloudfront-secure-static-site-templates-main&templateURL=https://s3.amazonaws.com/solution-builders-us-east-1/amazon-cloudfront-secure-static-site/latest/main.yaml)

2. If necessary, sign in with your AWS account credentials.
3. You should see a **Create stack** page, with pre-populated fields that specify the CloudFormation template. Choose the **Next** button at the bottom of the page.
4. On the **Specify stack details** page, enter values for the
   following fields:

   - **SubDomain:** The subdomain for your registered domain name. Viewers use the subdomain to access your website, for example: www.example.com. We recommend using the default value of **www** as the subdomain.
   - **DomainName:** Your registered domain name, such as example.com. This domain must be pointed to a Route 53 hosted zone.
   - **HostedZoneId** The Route 53 Hosted Zone Id containing the domain being used.
   - **CreateApex:** Optionally create an Alias to the domain apex (example.com) in your CloudFront configuration. Default is [no]

   After entering values, choose the **Next** button.

5. On the **Configure stack options** page, you can optionally [add tags and other stack options](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-console-add-tags.html). When finished, choose the **Next** button.
6. On the **Review** page, you must scroll down and check the two boxes in the **Capabilities** section:

   - **I acknowledge that AWS CloudFormation might create IAM resources with custom names.**
   - **I acknowledge that AWS CloudFormation might require the following capability: CAPABILITY_AUTO_EXPAND**

   These capabilities allow CloudFormation to create an IAM role that allows access
   to the stack’s resources, and to name the resources dynamically.

7. Choose the **Create stack** button.
8. Wait for the CloudFormation stack to launch. The stack launches some nested stacks, and can take several minutes to finish. When it’s launched, the **Status** changes to **CREATE_COMPLETE**.
9. After the stack is launched, go to **www.example.com** to view your website (replace **example.com** with your domain name). You should see the website’s default content:

   ![Static website page](./docs/images/static-website.png)

**To replace the website’s default content with your own**

1. Go to the [Amazon S3 console](https://s3.console.aws.amazon.com/s3/home).
1. Choose the bucket whose name begins with **amazon-cloudfront-secure-static-site-s3bucketroot-**.
   > **Note:** Make sure to choose the bucket with **s3bucketroot** in its name, not **s3bucketlogs**. The bucket with **s3bucketroot** in its name contains the content. The one with **s3bucketlogs** contains only log files.
1. In the bucket, delete the default content, then upload your own.

## Customizing the Solution

### Updating the site Response Headers

To change the Response Header Policy of the site:

1. Make your changes by editing ResponseHeadersPolicy in `templates/cloudfront-site.yaml`. Here you can modify any of the headers for Strict-Transport-Security, Content-Security-Policy, X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, and Referrer-Policy. 
2. Deploy the solution using one of described methods

## Contributing

Contributions are welcome. Please read the [code of conduct](CODE_OF_CONDUCT.md) and the [contributing guidelines](CONTRIBUTING.md).

## License Summary

This project is licensed under the Apache-2.0 License.
