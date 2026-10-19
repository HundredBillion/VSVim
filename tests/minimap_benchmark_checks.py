"""Benchmark event-matching checks, including independently delayed Git state."""
import os
import unittest
from minimap_benchmark import edited_band_paint, process_rss


class BenchmarkChecks(unittest.TestCase):
    def test_waits_for_actual_edited_band_after_source_generation(self):
        source = dict(event='paint', unix_ns=110, generation=2, first_line_change=False)
        delayed_git = dict(event='paint', unix_ns=150, generation=2, first_line_change=True)
        stale = dict(event='paint', unix_ns=90, generation=1, first_line_change=True)
        selected = next(event for event in [stale, source, delayed_git] if edited_band_paint(event,1,100))
        self.assertIs(selected, delayed_git)
        self.assertEqual(selected['unix_ns']-100,50)

    def test_libproc_reads_current_process_memory(self):
        self.assertGreater(process_rss(os.getpid()),0)


if __name__ == '__main__':
    unittest.main()
