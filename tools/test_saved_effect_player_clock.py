import copy
from pathlib import Path
import unittest
from check_saved_effects import player_clock_failures


class SavedPlayerClockControls(unittest.TestCase):
    def fixture(self):
        case={'operation':'animation_presets.pulse','player':'AnimationPlayer','clip':'generated'}
        samples=[{'take':take,'players':[{}, {'AnimationPlayer':{'active':True,'callback_mode_process':1,
            'assigned_animation':'generated','playing':True,'position':position}}]}
            for take in (1,2) for position in (0.0,.25,.5)]
        return case,samples

    def test_actual_idle_clock_and_progress_required_for_both_takes(self):
        case,samples=self.fixture()
        self.assertEqual(player_clock_failures(case,samples),[])
        for field,value in [('callback_mode_process',2),('active',False),('assigned_animation','other'),('position',0.0)]:
            bad=copy.deepcopy(samples)
            for row in bad:
                if row['take']==2: row['players'][1]['AnimationPlayer'][field]=value
            self.assertTrue(player_clock_failures(case,bad),field)

    def test_frozen_manual_playing_flag_cannot_qualify(self):
        case,samples=self.fixture()
        for row in samples:
            row['players'][1]['AnimationPlayer'].update(playing=True,callback_mode_process=2,position=0.0)
        self.assertEqual(len(player_clock_failures(case,samples)),2)

    def test_every_selected_showcase_player_is_checked_and_spriteframes_is_separate(self):
        case,samples=self.fixture()
        case['playbacks']=[{'player':'AnimationPlayer','redo_clip':'generated'},{'player':'Nested/Other','redo_clip':'other'}]
        self.assertTrue(player_clock_failures(case,samples))
        self.assertEqual(player_clock_failures({'operation':'animation_fx.sprite_frames'},[]),[])

    def test_renderer_only_selected_playback_gets_idle_clock_before_play(self):
        text=(Path(__file__).resolve().parents[1]/'test_project/tools/render_saved_effects.gd').read_text()
        start=text.index('func _play_saved(');end=text.index('func _player_times(',start)
        function=text[start:end]
        self.assertLess(function.index('ANIMATION_CALLBACK_MODE_PROCESS_IDLE'),function.index('player.play(clip)'))
        self.assertLess(function.index('player.active = true'),function.index('player.play(clip)'))
        self.assertNotIn('.seek(',function)
        self.assertNotIn('.advance(',function)


if __name__=='__main__': unittest.main()
