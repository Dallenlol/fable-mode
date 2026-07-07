def validate_item(item):
    if item.qty <= 0:
        raise ValueError(f"bad qty for {item.sku}")
    if item.unit_price < 0:
        raise ValueError(f"negative price for {item.sku}")
