import logging
from decimal import Decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table("WeatherData")

    device_id = event["device_id"]
    count = event["count"]

    # TODO make bulk write
    for i in range(count):
        item = {
            "DeviceId": device_id,
            "Timestamp": event["timestamp"][i],
            "Temperature": Decimal(event["temperature"][i]),
            "Humidity": Decimal(event["humidity"][i]),
        }
        logger.info(f"PutItem: {item}")
        table.put_item(Item=item)

    print("PutItem succeeded")
