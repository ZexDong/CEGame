import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from collect_with_observer_fallback import has_started_ticking

class FallbackStartupTests(unittest.TestCase):
    def test_beginplay_is_not_a_started_gameplay_clock(self):
        session={'process_id':7,'process_token':'current'}
        state={**session,'snapshot_id':1,'game_state':{'combat':{'round_time_ms':0}}}
        self.assertFalse(has_started_ticking(state,session))
        state['snapshot_id']=2
        self.assertFalse(has_started_ticking(state,session))
        state['game_state']['combat']['round_time_ms']=16
        self.assertTrue(has_started_ticking(state,session))
        state['process_token']='previous-process'
        self.assertFalse(has_started_ticking(state,session))
