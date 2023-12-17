from decimal import Decimal

from data_receiving_lambda.main import handler


def test_data_conversion(mocker):
    m = mocker.patch("data_receiving_lambda.main.boto3")
    put_item_mock = mocker.Mock()
    m.resource().Table().put_item = put_item_mock

    event = {
        "device_id": "test_device",
        "count": 2,
        "timestamp": [1, 2],
        "temperature": [Decimal("1.00"), Decimal("2.00")],
        "humidity": [Decimal("3.00"), Decimal("4.00")],
    }

    handler(event, None)

    assert put_item_mock.call_count == 2
    assert put_item_mock.call_args_list[0][1]["Item"] == {
        "DeviceId": "test_device",
        "Timestamp": 1,
        "Temperature": Decimal("1.00"),
        "Humidity": Decimal("3.00"),
    }
    assert put_item_mock.call_args_list[1][1]["Item"] == {
        "DeviceId": "test_device",
        "Timestamp": 2,
        "Temperature": Decimal("2.00"),
        "Humidity": Decimal("4.00"),
    }
