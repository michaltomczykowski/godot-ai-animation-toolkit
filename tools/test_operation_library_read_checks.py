import copy
import hashlib
import unittest
from operation_library_read_checks import derive

def row():
    path='res://animation_toolkit/history_contracts/malformed.json'
    raw=b'{bad-json'
    obs={'path':path,'exists':True,'bytes_hex':raw.hex(),'sha256':hashlib.sha256(raw).hexdigest()}
    return {'op':'template_list','request':{'op':'template_list','library_path':path},'file_before':obs,'file_after':copy.deepcopy(obs),'before':{'fixture':'authored'},'after':{'fixture':'authored'},'failed_before':False,'history_before':3,'history_after':3,'global_before':4,'global_after':4,'errors_before':0,'errors_after':0,'errors':[],'response':{'error':{'code':'INVALID_PARAMS','message':'Malformed JSON'}}}

class ReadTests(unittest.TestCase):
    def test_exact_refusal(self): self.assertEqual(set(derive(row()).values()),{'pass'})
    def test_unknown_is_not_typed(self):
        r=row();r['response']['error']['code']='UNKNOWN';self.assertEqual(derive(r)['typed_errors'],'fail')
    def test_mutation_and_engine_errors(self):
        for key,value in [('after',{'fixture':'changed'}),('history_after',8),('global_after',9)]:
            r=row();r[key]=value;self.assertEqual(derive(r)['source_unchanged'],'fail')
        r=row();r.update(errors_after=1,errors=['engine error']);self.assertEqual(derive(r)['reported_errors'],'fail')
    def test_hash_and_path_refused(self):
        r=row();r['file_before']['sha256']='0'*64
        with self.assertRaises(ValueError): derive(r)
        r=row();r['request']['library_path']='res://private.json'
        with self.assertRaises(ValueError): derive(r)
    def test_valid_document_cannot_be_refusal_evidence(self):
        r=row();raw=b'{}'
        for key in ['file_before','file_after']:r[key].update(bytes_hex=raw.hex(),sha256=hashlib.sha256(raw).hexdigest())
        with self.assertRaises(ValueError):derive(r)

if __name__=='__main__':unittest.main()
