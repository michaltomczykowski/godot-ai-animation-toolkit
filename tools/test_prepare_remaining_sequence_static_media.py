"""Offline corruption/staging controls; no engine, decode or visual approval."""
import copy
import io
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import prepare_remaining_sequence_static_media as s

SNAPSHOT=Path('F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30')
EVIDENCE=Path('E:/GodotAI-toolkit-release-2.0.0/20261014')
REPO=Path('G:/godot-ai-dev/godot-ai-animation-toolkit')


class Controls(unittest.TestCase):
    def test_selected_ids_are_exact_and_unique(self):
        rows=[{'id':identity}for identity in s.IDS]
        self.assertEqual(s.select_rows({'cases':rows}),rows)
        for values in (rows[:-1],rows+[rows[0]],[]):
            with self.assertRaisesRegex(ValueError,'missing/duplicate'):s.select_rows({'cases':values})

    def test_staged_resources_are_flat_immutable_and_self_contained(self):
        with tempfile.TemporaryDirectory()as directory:
            buffer=io.BytesIO()
            with zipfile.ZipFile(buffer,'w')as z:
                z.writestr('good.tscn','[gd_scene format=3]\n[node name="Original" type="Node3D"]\n')
                z.writestr('external.tscn','[ext_resource path="res://other.tscn"]\n')
                z.writestr('skin.tscn','[sub_resource type="Skin"]\n')
            with zipfile.ZipFile(buffer)as z:
                target=Path(directory)/'good.tscn';record=s.stage_member(z,'good.tscn',target)
                self.assertEqual(s.sha(target),record['sha256']);self.assertEqual(target.read_bytes(),z.read('good.tscn'))
                with self.assertRaises(FileExistsError):s.stage_member(z,'good.tscn',target)
                for member in ('../good.tscn','nested/good.tscn','external.tscn','skin.tscn'):
                    with self.subTest(member=member),self.assertRaises(ValueError):s.stage_member(z,member,Path(directory)/'bad.tscn')

    def test_wrong_preserved_bytes_refuse(self):
        with tempfile.TemporaryDirectory()as directory:
            p=Path(directory)/'receipt.json';p.write_bytes(b'original');digest=s.sha(p)
            self.assertEqual(s.pinned(p,digest)['sha256'],digest);p.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'changed preserved'):s.pinned(p,digest)


@unittest.skipUnless((SNAPSHOT/'motion_sequence_history_20261008/final-native-scenes.zip').is_file(),'private historical media unavailable')
class ActualInputs(unittest.TestCase):
    def test_actual_bounded_staging_retains_original_sources_and_copies_no_skinned_rigs(self):
        with tempfile.TemporaryDirectory()as directory:
            args=SimpleNamespace(repo=REPO,snapshot=SNAPSHOT,evidence=EVIDENCE,output=Path(directory)/'staged')
            result=s.prepare(args)
            self.assertEqual(result['minimum_new_capture_case_ids'],['secondary_branches_local_60','3d_local_create','3d_local_append'])
            self.assertEqual(result['full_sequence_reuse']['producer_source'],s.SEQUENCE_SOURCE)
            self.assertEqual(len(result['full_sequence_reuse']['movies']),2)
            self.assertTrue(all(m['recorded_full_decode']['frames']==5280 for m in result['full_sequence_reuse']['movies']))
            self.assertEqual([r['producer_source']for r in result['technical_pairs']['cases']],[s.SYNTHETIC_SOURCE]*3)
            self.assertEqual([r['producer_source']for r in result['static_pairs']],[s.CHAIN_SOURCE]*2)
            self.assertEqual(len(list(args.output.rglob('*.tscn'))),16)
            self.assertEqual(len(list(args.output.rglob('*.tres'))),3)
            self.assertEqual(list(args.output.rglob('*.fbx')),[]);self.assertEqual(list(args.output.rglob('*.mp4')),[])
            for row in result['technical_pairs']['cases']+result['static_pairs']:
                for rec in row['files'].values():self.assertEqual(s.sha(Path(rec['path'])),rec['sha256'])
            with self.assertRaisesRegex(ValueError,'preserve prior'):s.prepare(args)

    def test_actual_full_movie_green_flags_cannot_hide_bad_native_or_decode_schedule(self):
        original=s.read
        for fault in ('native_failure','duplicate_clock','decode_frames','route_binding','take'):
            def corrupt(path):
                value=copy.deepcopy(original(path))
                if path.name=='native-check.json':
                    if fault=='native_failure':value['runs'][0]['failures']=['real failure']
                    elif fault=='duplicate_clock':value['runs'][0]=copy.deepcopy(value['runs'][1])
                elif path.name=='media.json':
                    item=value['videos']['clean']
                    if fault=='decode_frames':item['decoded_frames']-=1
                    elif fault=='route_binding':item['route_sha256']='0'*64
                    elif fault=='take':item['render']['cases'][0]['takes']=1
                return value
            with self.subTest(fault=fault),patch.object(s,'read',side_effect=corrupt),self.assertRaises(ValueError):s.full_sequence(SNAPSHOT)


if __name__=='__main__':unittest.main()
