import json
import logging

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)


def handler(event, context):
    print('Event: ', event)
    dyn_res = boto3.resource("dynamodb")
    statement = 'SELECT * FROM "WeatherData";'
    output = dyn_res.meta.client.execute_statement(Statement=statement)
    print("Output:", output)
    for item in output["Items"]:
        logger.info("Weather Item: %s", item)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({ "message": "Hello World"}),
    }
