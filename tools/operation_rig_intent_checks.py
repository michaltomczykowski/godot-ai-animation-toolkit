"""Fixed-request native numeric rig intent predicates; no response/playback oracle."""
from copy import deepcopy
import math

LIMITS=('Requested effect is scoped to native 3D apply local transforms and chain create/append rest matrices/hierarchy at write/redo/reload. Other 2D, blend/reset/mirror/subtree variants remain pending for this channel. No separate chain pose-decomposition, skin/deformation, playback or visual promotion.')


def vector(x,y,z):return {'type':'Vector3','x':x,'y':y,'z':z}

def transform(angle,scale,origin,global_scale=False):
 c,s=math.cos(angle),math.sin(angle);sx,sy,sz=scale
 x=vector(c*sx,s*(sy if global_scale else sx),0)
 y=vector(-s*(sx if global_scale else sy),c*sy,0)
 return {'type':'Transform3D','basis':{'type':'Basis','x':x,'y':y,'z':vector(0,0,sz)},'origin':vector(*origin)}


def close(a,b):
 if isinstance(a,bool)or isinstance(b,bool):return type(a)is type(b)and a==b
 if type(a)in(int,float)and type(b)in(int,float):return math.isfinite(a)and math.isfinite(b)and abs(a-b)<1e-5
 if isinstance(a,dict)and isinstance(b,dict):return a.keys()==b.keys()and all(close(a[k],b[k])for k in a)
 if isinstance(a,list)and isinstance(b,list):return len(a)==len(b)and all(close(x,y)for x,y in zip(a,b))
 return type(a)is type(b)and a==b


def supported(row):
 return row.get('kind')=='3d'and ((row.get('op')=='pose_apply'and row.get('variant')=='apply')or(row.get('op')=='rig_chain'and row.get('variant')in('create','append')))


def effect(row):
 # The parent adapter binds exact source request, public span and all original gates.
 from operation_rig_scene_history_checks import case_identity
 case_identity(row)
 if not supported(row):return 'pending'
 try:
  before=row['before']['snapshot'];stages=[row['write']['state']['snapshot'],row['redo']['state']['snapshot'],row['persist_redo']['snapshot']]
  if row['op']=='pose_apply':
   old=before['children']['Skeleton'];bones=old['bones']
   if old['type']!='Skeleton3D'or [b['name']for b in bones]!=['arm_L','arm_R','untouched']:return 'fail'
   # Independent fixed-seed rest and request, never values from producer response.
   if not close(bones[0]['rest'],transform(.2,(1,1,1),(1,2,0))):return 'fail'
   expected=deepcopy(before);expected['children']['Skeleton']['bones'][0]['pose']=transform(.8,(1.6,.6,1.3),(1.4,1.7,0))
   if close(bones[0]['pose'],expected['children']['Skeleton']['bones'][0]['pose']):return 'fail'
   return 'pass'if all(close(stage,expected)for stage in stages)else'fail'
  append=row['variant']=='append';name='Skeleton'if append else'Generated'
  expected_rest=transform(math.pi/6,(1.4,.8,1.2),(.5,1,0),True)
  for stage in stages:
   result=deepcopy(stage);node=result['children'][name]
   if node['type']!='Skeleton3D'or not isinstance(node.get('bones'),list):return 'fail'
   oldbones=before['children']['Skeleton']['bones']if append else[]
   if len(node['bones'])!=len(oldbones)+1:return 'fail'
   bone=node['bones'][-1]
   if bone.get('name')!='tool'or type(bone.get('parent'))is not int or bone['parent']!=(0 if append else -1)or bone.get('enabled')is not True:return 'fail'
   if not close(bone.get('rest'),expected_rest):return 'fail'
   if append:
    if not close(node['bones'][:-1],oldbones):return 'fail'
    node['bones'].pop()
   else:del result['children'][name]
   if not close(result,before):return 'fail'
  return 'pass'
 except (KeyError,TypeError,IndexError):return 'fail'
