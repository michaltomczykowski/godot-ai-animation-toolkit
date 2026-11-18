import unittest,tempfile
from pathlib import Path
from unittest.mock import patch
import prepare_saved_bake_capture as p
class Controls(unittest.TestCase):
 def test_confined_user_resources(self):
  self.assertEqual(p.user_relative('user://bake_matrix_test_source.tscn'),Path('bake_matrix_test_source.tscn'))
  for value in ['res://test','user://../escape','user://C:/escape','user:///absolute',None]:
   with self.subTest(value=value),self.assertRaises(ValueError):p.user_relative(value)
 def test_existing_output_preserved(self):
  with tempfile.TemporaryDirectory() as d:
   target=Path(d);sentinel=target/'keep';sentinel.write_bytes(b'original')
   with self.assertRaisesRegex(ValueError,'preserve'):p.prepare(target,target,target)
   self.assertEqual(sentinel.read_bytes(),b'original')
 def test_unpinned_source_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);(root/'final-native-manifest.json').write_text('{}');(root/'closing-checkpoint.json').write_text('{"source":"foreign"}')
   with self.assertRaisesRegex(ValueError,'pin mismatch'):p.admit(root)
if __name__=='__main__':unittest.main()
