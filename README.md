# localstack-forgerock

This is an example of using [terraform](https://www.terraform.io/) to provision an [AWS API Gateway](https://aws.amazon.com/api-gateway/) to a [LocalStack](https://www.localstack.cloud/) instance

# Get a Hobby Account

1. Connect to <https://app.localstack.cloud/dashboard> and create a Hobby Account
1. Create an `AUTH_TOKEN` at <https://app.localstack.cloud/workspace/auth-token>
1. Add it to your bash profile so that it is available on your terminal and restart your terminal.

1. start localstack
   ```console
   docker-compose up
   ```
1. Deploy terraform
   ```console
   terraform init
   terraform apply --auto-approve
   ```
1. Execute request
   ```console
   BASE_URL=$(terraform output -raw base_url)
   curl ${BASE_URL} | jq .
   ```
   returns
   ```json
   {
     "message": "Hello, World!"
   }
   ```