import json
import logging

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    print('MAIN Event: ', event)
    logger.info('MAIN Event2: %s', event)

    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table("WeatherData")

    response = table.put_item(
       Item={
            "DeviceId": "ABCDEF",
            "Timestamp": 1234567890,
            "Temperature": 20,
            "Humidity": 50
        }
    )
