import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from review_receipts import write_json


class ReceiptControls(unittest.TestCase):
    @unittest.skipUnless(os.name=='nt','actual Windows delete-sharing contract')
    def test_actual_windows_read_handle_releases_before_bounded_atomic_rename(self):
        import ctypes
        import threading
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,
            ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]
        kernel.CreateFileW.restype=ctypes.c_void_p
        kernel.CloseHandle.argtypes=[ctypes.c_void_p]
        kernel.CloseHandle.restype=ctypes.c_int
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'receipt.json'
            write_json(path,{'state':'old'})
            handle=kernel.CreateFileW(str(path),0x80000000,3,None,3,0x80,None)
            self.assertNotEqual(handle,ctypes.c_void_p(-1).value)
            close=threading.Timer(0.075,lambda:kernel.CloseHandle(handle))
            close.start()
            try:
                write_json(path,{'state':'new'})
            finally:
                close.join()
            self.assertEqual(json.loads(path.read_text()),{'state':'new'})
            self.assertEqual(list(Path(directory).glob('*.tmp')),[])

    def test_transient_windows_reader_preserves_old_then_commits_same_staged_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'receipt.json'
            write_json(path,{'state':'old'})
            import os
            replace=os.replace
            attempts=[]
            def locked_once(temporary,target):
                attempts.append((temporary,temporary.read_bytes()))
                self.assertEqual(json.loads(path.read_text()),{'state':'old'})
                if len(attempts)==1:
                    error=PermissionError('temporary Windows sharing conflict')
                    error.winerror=32
                    raise error
                return replace(temporary,target)
            with patch('review_receipts.os.replace',side_effect=locked_once),patch('review_receipts.time.sleep'):
                write_json(path,{'state':'new'})
            self.assertEqual(attempts[0],attempts[1])
            self.assertEqual(json.loads(path.read_text()),{'state':'new'})
            self.assertEqual(list(Path(directory).glob('*.tmp')),[])

    def test_persistent_windows_lock_is_bounded_and_keeps_both_complete_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'receipt.json'
            write_json(path,{'state':'old'})
            error=PermissionError('persistent lock');error.winerror=5
            with patch('review_receipts.os.replace',side_effect=error)as replace,patch('review_receipts.time.sleep')as sleep:
                with self.assertRaises(PermissionError):write_json(path,{'state':'new'})
            self.assertEqual(replace.call_count,8)
            self.assertEqual(sleep.call_count,7)
            self.assertEqual(json.loads(path.read_text()),{'state':'old'})
            staged=list(Path(directory).glob('*.tmp'))
            self.assertEqual(len(staged),1)
            self.assertEqual(json.loads(staged[0].read_text()),{'state':'new'})

    def test_other_permission_errors_are_not_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'receipt.json'
            with patch('review_receipts.os.replace',side_effect=PermissionError('real permission denial'))as replace,patch('review_receipts.time.sleep')as sleep:
                with self.assertRaises(PermissionError):write_json(path,{'state':'new'})
            self.assertEqual(replace.call_count,1)
            sleep.assert_not_called()


if __name__=='__main__':unittest.main()
