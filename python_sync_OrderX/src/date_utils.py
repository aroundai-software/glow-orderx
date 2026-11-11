import logging
from datetime import datetime
from dateutil.relativedelta import relativedelta

def get_monthly_date_ranges(books_from_iso=None):
    """
    Returns a list of tuples (start_date, end_date) formatted as YYYYMMDD
    for each month from books_from_iso up to the current month.
    If books_from_iso is missing or invalid, defaults to beginning of current year.
    """
    try:
        if books_from_iso:
            start_date = datetime.fromisoformat(books_from_iso).replace(day=1)
        else:
            start_date = datetime.now().replace(month=1, day=1)
    except Exception:
        start_date = datetime.now().replace(month=1, day=1)

    end_date = datetime.now()
    ranges = []

    current = start_date
    while current <= end_date:
        # End of the current month
        next_month = current + relativedelta(months=1)
        month_end = next_month - relativedelta(days=1)
        
        # Format as YYYYMMDD
        ranges.append((
            current.strftime("%Y%m%d"),
            month_end.strftime("%Y%m%d")
        ))
        
        current = next_month

    return ranges

def get_current_fy_monthly_date_ranges():
    """
    Returns a list of tuples (start_date, end_date) formatted as YYYYMMDD
    for each month from the start of the current Indian Financial Year (April 1st)
    up to the current month.
    """
    now = datetime.now()
    if now.month >= 4:
        start_date = datetime(now.year, 4, 1)
    else:
        start_date = datetime(now.year - 1, 4, 1)
        
    end_date = datetime.now()
    ranges = []

    current = start_date
    while current <= end_date:
        next_month = current + relativedelta(months=1)
        month_end = next_month - relativedelta(days=1)
        
        ranges.append((
            current.strftime("%Y%m%d"),
            month_end.strftime("%Y%m%d")
        ))
        current = next_month

    return ranges
