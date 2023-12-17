import json
import logging
import time
from decimal import Decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def json_serialize(obj):
    if isinstance(obj, Decimal):
        return str(obj)
    raise TypeError(str(type(obj)))


def handler(event, context):
    query_params = event.get("queryStringParameters", {}) or {}
    current_timestamp = int(time.time())
    logger.info("current_timestamp: %r", current_timestamp)

    statement = [
        'SELECT * FROM "WeatherData"  WHERE "DeviceId" = \'device_1\''
    ]
    if gt := query_params.get("gt"):
        statement.append(f' AND "Timestamp" > {int(gt)}')
    if lt := query_params.get("lt"):
        statement.append(f' AND "Timestamp" < {int(lt)}')
    if minutes := query_params.get("last"):
        statement.append(f' AND "Timestamp" > {current_timestamp - 60 * int(minutes)}')

    # By default, return the last 5 minutes of data
    if not any([gt, lt, minutes]):
        statement.append(f' AND "Timestamp" > {current_timestamp - 60 * 5}')

    dyn_res = boto3.resource("dynamodb")
    output = dyn_res.meta.client.execute_statement(Statement="".join(statement))

    timestamps = [item["Timestamp"] for item in output["Items"]]
    temperatures = [item["Temperature"] for item in output["Items"]]
    humidities = [item["Humidity"] for item in output["Items"]]

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "timestamps": timestamps,
                "temperatures": temperatures,
                "humidities": humidities
            },
            default=json_serialize,
        ),
    }
