from core.models import LineItem, Order
from services.invoicing import invoice_summary


def create_order(payload):
    order = Order(order_id=payload["id"])
    for row in payload.get("items", []):
        order.items.append(LineItem(row["sku"], float(row["price"]), int(row["qty"])))
    return order


def order_summary_endpoint(payload):
    return {"summary": invoice_summary(create_order(payload))}
