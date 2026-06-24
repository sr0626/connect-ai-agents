"""Customer-profile lookup for the Nova Sonic self-service agent.

Invoked by the Amazon Connect contact flow at the START of a call (an "Invoke
AWS Lambda function" block), before the AI agent runs. It reads the caller's
number (ANI) from the contact event, looks the caller up in the `customers`
table, and returns a ready-to-speak **greeting** plus the customer's name so the
flow can greet a known caller by name. Unknown callers get a generic greeting.

The table stores first + last name (and is the home for any future caller
personalization — tier, preferences, etc.); greetings use the **first name**
only for now. Keep it decoupled from the orders table.

Responses are kept FLAT (top-level string fields) + a composed `greeting`, so
the flow can play `$.External.greeting` directly and store `$.External.customer_name`
as a contact attribute for the agent to use later.
"""

import json
import logging
import os
import re
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_TABLE = boto3.resource("dynamodb").Table(os.environ["CUSTOMERS_TABLE"])
_COMPANY = os.environ.get("COMPANY_NAME", "our customer support line")


def _params(event):
    """Pull parameters from either a Connect or a direct/test invocation."""
    if isinstance(event, dict):
        details = event.get("Details")
        if isinstance(details, dict) and "Parameters" in details:
            return details["Parameters"] or {}
        return event
    return {}


def _caller_ani(event):
    """The caller's own number (ANI) from the Connect contact event, if present.

    Connect puts the calling number at
    event["Details"]["ContactData"]["CustomerEndpoint"]["Address"] (E.164).
    """
    try:
        return event["Details"]["ContactData"]["CustomerEndpoint"]["Address"] or ""
    except (KeyError, TypeError):
        return ""


def _normalize_phone(raw):
    """Best-effort E.164 (+1) normalization, matching order_lookup's logic."""
    raw = (raw or "").strip()
    had_plus = raw.startswith("+")
    digits = re.sub(r"\D", "", raw)
    if not digits:
        return ""
    if had_plus:
        return "+" + digits
    if len(digits) == 10:
        return "+1" + digits
    if len(digits) == 11 and digits.startswith("1"):
        return "+" + digits
    return "+" + digits


def lambda_handler(event, context):
    logger.info("customer_lookup EVENT: %s", json.dumps(event, default=str))
    result = _do_lookup(event)
    logger.info("customer_lookup RESULT: %s", json.dumps(result, default=str))
    return result


def _do_lookup(event):
    params = _params(event)
    # Prefer an explicitly passed phone (e.g. test invocations); else the ANI.
    phone_raw = (params.get("customer_phone") or params.get("phone") or "").strip()
    phone = _normalize_phone(phone_raw) if phone_raw else _normalize_phone(_caller_ani(event))
    logger.info("customer_lookup PARAMS: phone=%s", phone)

    first = last = ""
    if phone:
        item = _TABLE.get_item(Key={"phone": phone}).get("Item")
        if item:
            first = str(item.get("first_name", "")).strip()
            last = str(item.get("last_name", "")).strip()

    if first:
        # Personalized greeting — first name only for now. The full name is also
        # returned (customer_name) for the agent / later personalization.
        return {
            "found": "true",
            "first_name": first,
            "last_name": last,
            "customer_name": (first + " " + last).strip(),
            "greeting": f"Hi {first}, thanks for calling {_COMPANY}.",
        }

    # Unknown (or no ANI) -> generic greeting, no name.
    return {
        "found": "false",
        "first_name": "",
        "last_name": "",
        "customer_name": "",
        "greeting": f"Thanks for calling {_COMPANY}.",
    }
