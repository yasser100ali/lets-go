def service_fee(subtotal_cents: int) -> int:
    """5%, at least 50¢. Matches Pricing.serviceFee on iOS."""
    if subtotal_cents <= 0:
        return 0
    return max(50, round(subtotal_cents * 0.05))
