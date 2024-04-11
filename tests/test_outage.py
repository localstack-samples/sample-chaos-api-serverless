import pytest
import time
import boto3
import requests

# Replace with your LocalStack endpoint
LOCALSTACK_ENDPOINT = "http://localhost:4566"

# Replace with your LocalStack DynamoDB table name
DYNAMODB_TABLE_NAME = "Products"

# Replace with your Lambda function names
LAMBDA_FUNCTIONS = ["add-product", "get-product", "process-product-events"]


@pytest.fixture(scope="module")
def dynamodb_resource():
    return boto3.resource("dynamodb", endpoint_url=LOCALSTACK_ENDPOINT)


@pytest.fixture(scope="module")
def lambda_client():
    return boto3.client("lambda", endpoint_url=LOCALSTACK_ENDPOINT)


def test_dynamodb_table_exists(dynamodb_resource):
    tables = dynamodb_resource.tables.all()
    table_names = [table.name for table in tables]
    assert DYNAMODB_TABLE_NAME in table_names


def test_lambda_functions_exist(lambda_client):
    functions = lambda_client.list_functions()["Functions"]
    function_names = [func["FunctionName"] for func in functions]
    assert all(func_name in function_names for func_name in LAMBDA_FUNCTIONS)


def test_dynamodb_outage():
    outage_payload = [{"service": "dynamodb", "region": "us-east-1"}]
    requests.post(
        "http://outages.localhost.localstack.cloud:4566/outages", json=outage_payload
    )

    # Make a request to DynamoDB and assert an error
    url = "http://12345.execute-api.localhost.localstack.cloud:4566/dev/productApi"
    headers = {"Content-Type": "application/json"}
    data = {
        "id": "prod-1002",
        "name": "Super Widget",
        "price": "29.99",
        "description": "A versatile widget that can be used for a variety of purposes. Durable, reliable, and affordable.",
    }

    response = requests.post(url, headers=headers, json=data)

    assert "error" in response.text

    # Check if outage is running
    outage_status = requests.get(
        "http://outages.localhost.localstack.cloud:4566/outages"
    ).json()
    assert outage_payload == outage_status

    # Stop the outage
    requests.post("http://outages.localhost.localstack.cloud:4566/outages", json=[])

    # Check if outage is stopped
    outage_status = requests.get(
        "http://outages.localhost.localstack.cloud:4566/outages"
    ).json()
    assert not outage_status

    # Wait for a few seconds
    time.sleep(60)

    # Query if there are items in DynamoDB table
    dynamodb = boto3.resource("dynamodb", endpoint_url=LOCALSTACK_ENDPOINT)
    table = dynamodb.Table(DYNAMODB_TABLE_NAME)
    response = table.scan()
    items = response["Items"]
    print(items)
    assert "Super Widget" in [item["name"] for item in items]
