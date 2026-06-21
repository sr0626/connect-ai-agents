"""Refund-processing tool for the Nova Sonic self-service agent.

Invoked by Amazon Connect (AI agent flow-module tool / "Invoke Lambda function"
block). Validates that the order exists and is refundable, then conditionally
marks it refunded in DynamoDB. The conditional update makes the tool idempotent:
a second refund attempt on the same order returns already_refunded instead of
double processing.

Responses are kept FLAT with string values + a ready-to-speak `message`, because
Connect's flow-module / AI-agent tool layer reliably passes flat scalars only.
"""

import json
import logging
import os
import re
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_TABLE = boto3.resource("dynamodb").Table(os.environ["ORDERS_TABLE"])


def _params(event):
    if isinstance(event, dict):
        details = event.get("Details")
        if isinstance(details, dict) and "Parameters" in details:
            return details["Parameters"] or {}
        return event
    return {}


def _normalize_order_id(raw):
    """Map spoken/loose order ids to the canonical ORD-#### form."""
    s = raw.strip().upper()
    if not s:
        return ""
    digits = re.sub(r"\D", "", s)
    if s == digits:
        return f"ORD-{digits}"
    m = re.match(r"^ORD[\s\-_]?(\d+)$", s)
    if m:
        return f"ORD-{m.group(1)}"
    return s


def lambda_handler(event, context):
    logger.info("process_refund EVENT: %s", json.dumps(event, default=str))
    result = _do_refund(event)
    logger.info("process_refund RESULT: %s", json.dumps(result, default=str))
    return result


def _do_refund(event):
    params = _params(event)
    logger.info("process_refund PARAMS: %s", json.dumps(params, default=str))
    order_id = _normalize_order_id(params.get("order_id") or params.get("orderId") or "")

    if not order_id:
        return {"success": "false", "message": "An order ID is required to process a refund."}

    item = _TABLE.get_item(Key={"order_id": order_id}).get("Item")
    if not item:
        return {"success": "false", "message": f"No order found with id {order_id}."}

    if item.get("status") == "refunded":
        return {
            "success": "true",
            "already_refunded": "true",
            "order_id": order_id,
            "message": f"Order {order_id} was already refunded.",
        }

    if not bool(item.get("refundable", False)):
        return {
            "success": "false",
            "order_id": order_id,
            "message": f"Order {order_id} is not eligible for a refund.",
        }

    now = datetime.now(timezone.utc).isoformat()
    try:
        _TABLE.update_item(
            Key={"order_id": order_id},
            UpdateExpression="SET #s = :refunded, refunded_at = :now, refundable = :notref",
            ConditionExpression="attribute_not_exists(refunded_at)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":refunded": "refunded", ":now": now, ":notref": False},
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return {
                "success": "true",
                "already_refunded": "true",
                "order_id": order_id,
                "message": f"Order {order_id} was already refunded.",
            }
        raise

    amount = str(item.get("amount", ""))
    return {
        "success": "true",
        "already_refunded": "false",
        "order_id": order_id,
        "amount": amount,
        "message": f"A refund of {amount} dollars for order {order_id} has been processed.",
    }
