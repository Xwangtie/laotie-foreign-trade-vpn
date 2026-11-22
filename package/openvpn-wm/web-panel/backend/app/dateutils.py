"""日期工具（UTC 内使用，展示层转本地时区）。"""

from __future__ import annotations

import calendar
from datetime import datetime


def add_months(dt: datetime, months: int) -> datetime:
    if months <= 0:
        return dt
    month_index = dt.year * 12 + (dt.month - 1) + months
    year, zero_month = divmod(month_index, 12)
    month = zero_month + 1
    day = min(dt.day, calendar.monthrange(year, month)[1])
    return dt.replace(year=year, month=month, day=day)
