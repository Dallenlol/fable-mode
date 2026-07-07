from dataclasses import dataclass, field


@dataclass
class LineItem:
    sku: str
    unit_price: float  # dollars, as entered by staff
    qty: int


@dataclass
class Order:
    order_id: str
    items: list = field(default_factory=list)
    refunded_skus: set = field(default_factory=set)
