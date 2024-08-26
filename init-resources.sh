#!/bin/sh

apt-get -y install jq

echo "Create DynamoDB table..."
awslocal dynamodb create-table \
        --table-name Products \
        --attribute-definitions AttributeName=id,AttributeType=S \
        --key-schema AttributeName=id,KeyType=HASH \
         --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region us-east-1

echo "Add Product Lambda..."
awslocal lambda create-function \
  --function-name add-product \
  --runtime java17 \
  --handler lambda.AddProduct::handleRequest \
  --memory-size 1024 \
  --zip-file fileb:///etc/localstack/init/ready.d/target/product-lambda.jar \
  --region us-east-1 \
  --role arn:aws:iam::000000000000:role/productRole \
  --environment Variables={AWS_REGION=us-east-1}

echo "Get Product Lambda..."
awslocal lambda create-function \
  --function-name get-product \
  --runtime java17 \
  --handler lambda.GetProduct::handleRequest \
  --memory-size 1024 \
  --zip-file fileb:///etc/localstack/init/ready.d/target/product-lambda.jar \
  --region us-east-1 \
  --role arn:aws:iam::000000000000:role/productRole \
  --environment Variables={AWS_REGION=us-east-1}

export REST_API_ID=12345

echo "Create Rest API..."
awslocal apigateway create-rest-api --name quote-api-gateway --tags '{"_custom_id_":"12345"}' --region us-east-1

echo "Export Parent ID..."
export PARENT_ID=$(awslocal apigateway get-resources --rest-api-id $REST_API_ID --region=us-east-1 | jq -r '.items[0].id')

echo "Export Resource ID..."
export RESOURCE_ID=$(awslocal apigateway create-resource --rest-api-id $REST_API_ID --parent-id $PARENT_ID --path-part "productApi" --region=us-east-1 | jq -r '.id')

echo "RESOURCE ID:"
echo $RESOURCE

echo "Put GET Method..."
awslocal apigateway put-method \
--rest-api-id $REST_API_ID \
--resource-id $RESOURCE_ID \
--http-method GET \
--request-parameters "method.request.path.productApi=true" \
--authorization-type "NONE" \
--region=us-east-1

echo "Put POST Method..."
awslocal apigateway put-method \
--rest-api-id $REST_API_ID \
--resource-id $RESOURCE_ID \
--http-method POST \
--request-parameters "method.request.path.productApi=true" \
--authorization-type "NONE" \
--region=us-east-1


echo "Update GET Method..."
awslocal apigateway update-method \
  --rest-api-id $REST_API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --patch-operations "op=replace,path=/requestParameters/method.request.querystring.param,value=true" \
  --region=us-east-1


echo "Put POST Method Integration..."
awslocal apigateway put-integration \
  --rest-api-id $REST_API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:add-product/invocations \
  --passthrough-behavior WHEN_NO_MATCH \
  --region=us-east-1

echo "Put GET Method Integration..."
awslocal apigateway put-integration \
  --rest-api-id $REST_API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method GET \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:get-product/invocations \
  --passthrough-behavior WHEN_NO_MATCH \
  --region=us-east-1

echo "Create DEV Deployment..."
awslocal apigateway create-deployment \
  --rest-api-id $REST_API_ID \
  --stage-name dev \
  --region=us-east-1
