"""Order-lookup tool for the Nova Sonic self-service agent.

Invoked by Amazon Connect (AI agent flow-module tool / "Invoke Lambda function"
block). Accepts an order id and/or the caller's phone number and returns the
order status from DynamoDB. When neither is given (e.g. the caller says "use my
number" / "use the caller ID"), it falls back to the caller's own calling number
(ANI) taken from the contact event — no flow wiring needed.

IMPORTANT: responses are kept FLAT (top-level string key/values) — Connect's
flow-module / AI-agent tool layer reliably passes flat scalar fields but drops
nested objects/arrays, so the agent could not read fields nested under `order`.
A ready-to-speak `message` is always included for the voice agent to read out.

Event shape is normalized to support both Connect invocations (parameters under
event["Details"]["Parameters"]) and direct/test invocations (top-level).
"""

import json
import logging
import os
import re
import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_TABLE = boto3.resource("dynamodb").Table(os.environ["ORDERS_TABLE"])
_GSI = os.environ.get("PHONE_GSI_NAME", "by-phone")


def _params(event):
    """Pull tool parameters from either a Connect or a direct invocation."""
    if isinstance(event, dict):
        details = event.get("Details")
        if isinstance(details, dict) and "Parameters" in details:
            return details["Parameters"] or {}
        return event
    return {}


def _normalize_phone(raw):
    """Best-effort E.164 (+1) normalization for spoken / loosely-formatted phones.

    Strips ALL formatting (spaces, dashes, parens, a leading '+') and rebuilds
    +<countrycode><number>, so '2146817675', '+1 214 681 7675', '(214) 681-7675',
    and '12146817675' all become '+12146817675'.
    """
    raw = raw.strip()
    had_plus = raw.startswith("+")
    digits = re.sub(r"\D", "", raw)
    if not digits:
        return ""
    if had_plus:
        return "+" + digits          # caller gave an explicit country code
    if len(digits) == 10:
        return "+1" + digits         # US 10-digit -> +1
    if len(digits) == 11 and digits.startswith("1"):
        return "+" + digits          # 1 + 10 digits
    return "+" + digits              # fallback


def _caller_ani(event):
    """The caller's own number (ANI) from the Connect contact event, if present.

    Connect puts the calling number at
    event["Details"]["ContactData"]["CustomerEndpoint"]["Address"] (E.164, e.g.
    "+12146817675"). Returns "" when absent (e.g. a direct/test invocation).
    """
    try:
        addr = event["Details"]["ContactData"]["CustomerEndpoint"]["Address"]
    except (KeyError, TypeError):
        return ""
    return _normalize_phone(addr or "")


def _normalize_order_id(raw):
    """Map spoken/loose order ids to the canonical ORD-#### form.

    Handles 'ord-1001', 'ORD 1001', 'ORD1001', 'ORD_1001', and bare '1001'.
    """
    s = raw.strip().upper()
    if not s:
        return ""
    digits = re.sub(r"\D", "", s)
    if s == digits:  # caller said only the number
        return f"ORD-{digits}"
    m = re.match(r"^ORD[\s\-_]?(\d+)$", s)
    if m:
        return f"ORD-{m.group(1)}"
    return s


def _flat_order(order):
    """Trim a DynamoDB item to flat string fields the agent can speak."""
    return {
        "order_id": str(order.get("order_id", "")),
        "status": str(order.get("status", "unknown")),
        "item": str(order.get("item", "")),
        "amount": str(order.get("amount", "")),
        "customer_name": str(order.get("customer_name", "")),
        "refundable": "yes" if order.get("refundable", False) else "no",
    }


def lambda_handler(event, context):
    logger.info("order_lookup EVENT: %s", json.dumps(event, default=str))
    result = _do_lookup(event)
    logger.info("order_lookup RESULT: %s", json.dumps(result, default=str))
    return result


def _do_lookup(event):
    params = _params(event)
    logger.info("order_lookup PARAMS: %s", json.dumps(params, default=str))
    order_id = _normalize_order_id(params.get("order_id") or params.get("orderId") or "")
    phone_raw = (params.get("customer_phone") or params.get("phone") or "").strip()

    # Look up by explicit order id first.
    if order_id:
        item = _TABLE.get_item(Key={"order_id": order_id}).get("Item")
        if not item:
            return {"found": "false", "message": f"No order found with id {order_id}."}
        flat = _flat_order(item)
        flat["found"] = "true"
        # Note: `refundable` is intentionally NOT spoken in the message — it's an
        # internal eligibility flag (still returned as a field for the agent to
        # reason about refunds), not something to read out to the caller.
        flat["message"] = (
            f"Order {flat['order_id']} for {flat['customer_name']}: {flat['item']}, "
            f"status {flat['status']}, amount {flat['amount']} dollars."
        )
        return flat

    # Otherwise list the caller's orders by phone number (flattened to a summary).
    # An explicitly given number wins; if none is usable (blank, or a non-numeric
    # phrase like "my number" / "caller ID" that normalizes to empty), fall back
    # to the caller's own calling number (ANI) from the contact event.
    phone = _normalize_phone(phone_raw) if phone_raw else ""
    used_ani = False
    if not phone:
        phone = _caller_ani(event)
        used_ani = bool(phone)

    if phone:
        resp = _TABLE.query(
            IndexName=_GSI,
            KeyConditionExpression=Key("customer_phone").eq(phone),
        )
        items = resp.get("Items", [])
        whose = "your calling number" if used_ani else phone
        if not items:
            return {"found": "false", "message": f"No orders found for {whose}."}
        parts = [
            f"{o.get('order_id')} ({o.get('item')}, {o.get('status')}, "
            f"{o.get('amount')} dollars)"
            for o in items
        ]
        lead = f"Found {len(items)} order(s)"
        lead += " for your calling number" if used_ani else ""
        return {
            "found": "true",
            "count": str(len(items)),
            "customer_name": str(items[0].get("customer_name", "")),
            "used_caller_id": "yes" if used_ani else "no",
            "message": lead + ": " + "; ".join(parts) + ".",
        }

    return {
        "found": "false",
        "message": "Provide an order ID or a customer phone number to look up an order.",
    }
