"""Exercise real pipe buffering, process exit and incomplete protocol lines."""

import subprocess
import sys
import time
import unittest

from .rl_env import JednaVsProcessEnv


class EngineIOTest(unittest.TestCase):
    def setUp(self):
        self.env = JednaVsProcessEnv('unused.rb', 'unused', persistent_engine=False)

    def tearDown(self):
        self.env.close()

    def start_process(self, code):
        self.env.proc = subprocess.Popen(
            [sys.executable, '-c', code],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
        self.env._deadline = time.monotonic() + 2

    def test_drains_game_end_after_engine_exit(self):
        self.start_process('print(\'{"type":"game_end","winner":"agent1"}\')')
        self.env.proc.wait(timeout=2)

        self.assertEqual(self.env._read(), {'type': 'game_end', 'winner': 'agent1'})
        self.assertIsNone(self.env._read())

    def test_step_preserves_buffered_win_even_if_action_write_hits_closed_pipe(self):
        self.start_process('print(\'{"type":"game_end","winner":"agent1"}\')')
        self.env.proc.wait(timeout=2)

        _obs, reward, terminated, truncated, info = self.env.step(0)

        self.assertTrue(terminated)
        self.assertFalse(truncated)
        self.assertEqual(reward, 1.0)
        self.assertEqual(info['winner'], 'agent1')

    def test_reads_multiple_buffered_messages_without_waiting_for_process_exit(self):
        self.start_process(
            'import sys; '
            'print(\'{"type":"notification"}\\n{"type":"game_end"}\', flush=True); '
            'sys.stdin.read()'
        )

        self.assertEqual(self.env._read()['type'], 'notification')
        self.assertEqual(self.env._read()['type'], 'game_end')
        self.assertIsNone(self.env.proc.poll())

    def test_partial_line_obeys_deadline(self):
        self.start_process('import sys; sys.stdout.write(\'{"type":\'); sys.stdout.flush(); sys.stdin.read()')
        self.env._deadline = time.monotonic() + 0.2

        self.assertIsNone(self.env._read())
        self.assertTrue(self.env._timed_out)
        _obs, _reward, terminated, truncated, info = self.env.step(0)
        self.assertFalse(terminated)
        self.assertTrue(truncated)
        self.assertEqual(info['reason'], 'timeout')


if __name__ == '__main__':
    unittest.main()
