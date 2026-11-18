"""DST regression checks; run with python3 -m unittest discover -s analysis/tests."""
import importlib.util
from datetime import datetime, timedelta
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('fuel_mix', Path(__file__).parents[1] / 'data/fetch_ercot_fuel_mix.py')
fuel_mix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fuel_mix)


class CalendarTests(unittest.TestCase):
    def day(self, date, spring=False, fall=False):
        d = datetime.fromisoformat(date)
        labels = [f'{i // 4}:{i % 4 * 15:02}' for i in range(1, 96)] + ['0:00']
        if spring:
            labels = [s for s in labels if s not in ('2:15', '2:30', '2:45', '3:00')]
        if fall:
            labels += ['01:15 (DST)', '01:30 (DST)', '01:45 (DST)', '02:00 (DST)']
        return d, {fuel_mix.interval_start(d, label): {} for label in labels}

    def test_spring_forward(self):
        d, cells = self.day('2025-03-09', spring=True)
        self.assertEqual(len(cells), 92)
        fuel_mix.validate_calendar(cells, d, d)
        self.assertFalse(any(start.hour == 2 for start, flag in cells))
        cells[(d + timedelta(hours=2), 'N')] = {}
        with self.assertRaises(ValueError):
            fuel_mix.validate_calendar(cells, d, d)

    def test_fall_back(self):
        d, cells = self.day('2025-11-02', fall=True)
        self.assertEqual(len(cells), 100)
        fuel_mix.validate_calendar(cells, d, d)
        self.assertEqual(sum(flag == 'Y' for start, flag in cells), 4)
        self.assertIn((d + timedelta(hours=23, minutes=45), 'N'), cells)
        # Keeping 100 rows is insufficient if repeated flags are put on the wrong hour.
        cells[(d + timedelta(hours=2), 'Y')] = cells.pop((d + timedelta(hours=1), 'Y'))
        with self.assertRaises(ValueError):
            fuel_mix.validate_calendar(cells, d, d)


class ThroughTests(unittest.TestCase):
    def test_default_end_is_last_complete_month(self):
        # a workbook that runs to a month end ends there; a month cut short is left out
        full = {(datetime(2026, 8, 31, 23, 45), 'N'): {}}
        self.assertEqual(fuel_mix.last_complete_month_end(full), datetime(2026, 8, 31))
        part = {(datetime(2026, 9, 14, 23, 45), 'N'): {}}
        self.assertEqual(fuel_mix.last_complete_month_end(part), datetime(2026, 8, 31))
        dec = {(datetime(2026, 12, 31, 23, 45), 'N'): {}}
        self.assertEqual(fuel_mix.last_complete_month_end(dec), datetime(2026, 12, 31))
        # a month end whose last day stops partway is cut short too
        short = {(datetime(2026, 8, 31, 11, 45), 'N'): {}}
        self.assertEqual(fuel_mix.last_complete_month_end(short), datetime(2026, 7, 31))
        # only the first interval of a new month counts as that month cut short
        first = {(datetime(2026, 9, 1, 0, 0), 'N'): {}}
        self.assertEqual(fuel_mix.last_complete_month_end(first), datetime(2026, 8, 31))


if __name__ == '__main__':
    unittest.main()
