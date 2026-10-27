"""Independent fixed saved-walk native reference comparisons; no tool grade flags as oracles."""
import math
import struct

BONES=('B-hips','B-thigh.L','B-shin.L','B-foot.L','B-toe.L','B-thigh.R','B-shin.R','B-foot.R','B-toe.R')
def finite(v):return type(v) in (int,float) and math.isfinite(v)
def f(v):return struct.unpack('<f',struct.pack('<f',v))[0]
def add(a,b):return [f(x+y) for x,y in zip(a,b)]
def sub(a,b):return [f(x-y) for x,y in zip(a,b)]
def mul(a,k):return [f(x*k) for x in a]
def dot(a,b):return f(f(f(a[0]*b[0])+f(a[1]*b[1]))+f(a[2]*b[2]))
def cross(a,b):return [f(f(a[1]*b[2])-f(a[2]*b[1])),f(f(a[2]*b[0])-f(a[0]*b[2])),f(f(a[0]*b[1])-f(a[1]*b[0]))]
def length(a):return f(math.sqrt(max(0,dot(a,a))))
def unit(a):
 size=length(a);return [f(x/size) for x in a] if size>0 else [0.,0.,0.]
def flat(a,b):
 d=sub(a,b);return f(math.sqrt(f(f(d[0]*d[0])+f(d[2]*d[2]))))
def r4(v):return (math.floor(v*10000+.5) if v>=0 else math.ceil(v*10000-.5))/10000

def equal(a,b):
 if isinstance(b,bool):return type(a) is bool and a==b
 if isinstance(b,(int,float)):return finite(a) and abs(a-b)<=1e-12
 if isinstance(b,list):return isinstance(a,list) and len(a)==len(b) and all(equal(x,y) for x,y in zip(a,b))
 if isinstance(b,dict):return isinstance(a,dict) and all(k in a and equal(a[k],v) for k,v in b.items())
 return type(a) is type(b) and a==b

def reference_valid(ref,op):
 n=8 if op=='sample' else 120
 if not isinstance(ref,dict) or ref.get('eligible') is not True or ref.get('kind')!='fresh_saved_scene_native_Player' or ref.get('scene')!='res://repair_motion_fixture.tscn' or ref.get('clip')!='repair_probe_walk' or ref.get('samples')!=n or ref.get('root_track_before')!='Dummy:position' or ref.get('root_track_played')!='Dummy:position':return False
 if ref.get('pose_source')!='native_extracted_world_before_root_addition' or type(ref.get('root_index')) is not int or ref['root_index']!=20 or type(ref.get('root_type')) is not int or ref['root_type']!=1 or ref.get('root_local') is not True or not finite(ref.get('clip_length')) or ref['clip_length']!=1 or type(ref.get('clip_loop_mode')) is not int or ref['clip_loop_mode']!=1:return False
 if not equal(ref.get('root_basis'),[[1,0,0],[0,1,0],[0,0,1]]) or not equal(ref.get('root_start'),[0,0,0]):return False
 endpoint=ref.get('root_endpoint')
 if not isinstance(endpoint,list) or len(endpoint)!=3 or not all(finite(v) for v in endpoint):return False
 frames=ref.get('frames',[])
 if len(frames)!=n:return False
 for i,row in enumerate(frames):
  if not equal(row.get('at'),i/(n-1)) or not equal(row.get('position'),0. if i==n-1 else i/(n-1)) or row.get('assigned')!='repair_probe_walk' or type(row.get('process')) is not int or row['process']!=2 or not finite(row.get('speed')) or row['speed']!=1:return False
  root=row.get('root_sample')
  if not isinstance(root,list) or len(root)!=3 or not all(finite(v) for v in root):return False
  if i==0 and not equal(root,ref['root_start']):return False
  if i==n-1 and not equal(root,endpoint):return False
  points=row.get('points',{})
  if set(points)!=set(BONES) or any(not isinstance(v,list) or len(v)!=3 or not all(finite(x) for x in v) for v in points.values()):return False
 for field in ('up','forward','lateral'):
  v=ref.get(field)
  if not isinstance(v,list) or len(v)!=3 or not all(finite(x) for x in v) or abs(length(v)-1)>1e-5:return False
 for bone in ('B-foot.L','B-foot.R'):
  if max(length(sub(row['points'][bone],frames[0]['points'][bone])) for row in frames)<=.02:return False
 if not equal(ref['up'],[0,1,0]) or abs(dot(ref['forward'],ref['up']))>1e-5 or abs(dot(ref['lateral'],ref['up']))>1e-5 or abs(dot(ref['forward'],ref['lateral']))>1e-5:return False
 return all(finite(ref.get('legs',{}).get(s)) and ref['legs'][s]>0 for s in ('l','r')) and all(isinstance(ref.get('rest_feet',{}).get(s),list) and len(ref['rest_feet'][s])==3 and all(finite(v) for v in ref['rest_feet'][s]) for s in ('l','r'))

def sample_effect(result,ref):
 if not reference_valid(ref,'sample'):return False
 times=[i/7 for i in range(8)]
 if not equal(result,{'length':1,'sample_count':8,'times':times,'contact_threshold':.02,'missing_bones':[],'bones_truncated':False,'undoable':False}):return False
 if set(result.get('bones',{}))!={'B-foot.L','B-foot.R'} or set(result.get('feet',{}))!={'l','r'}:return False
 for side in ('l','r'):
  name='B-foot.'+side.upper();positions=[[r4(v) for v in row['points'][name]] for row in ref['frames']]
  heights=[r4(dot(row['points'][name],ref['up'])) for row in ref['frames']]
  windows=[];start=None
  for i,h in enumerate(heights):
   contact=h<=min(heights)+.02
   if contact and start is None:start=times[i]
   elif not contact and start is not None:windows.append({'start':start,'end':times[i-1]});start=None
  if start is not None:windows.append({'start':start,'end':times[-1]})
  if not equal(result['bones'][name],{'positions':positions}) or not equal(result['feet'][side],{'bone':name,'heights':heights,'min_height':r4(min(heights)),'height_range':r4(max(heights)-min(heights)),'contacts':windows}):return False
 return True


def slide(times,points,ground,threshold):
 windows=[];start=None;anchor=last=None;path=net=total_path=worst=contact_time=0.
 for i,p in enumerate(points):
  contact=abs(p[1]-ground)<=threshold
  if contact:
   contact_time+=min(times[min(i+1,len(times)-1)]-times[i],times[i]-times[max(i-1,0)]) if i>0 else times[1]-times[0]
   if start is None:start=times[i];anchor=last=p;path=0.
   else:last=p;path+=flat(points[i-1],p)
  if start is not None and (not contact or i==len(times)-1):
   distance=flat(anchor,last);net+=distance;total_path+=path;worst=max(worst,distance)
   windows.append({'start':r4(start),'end':r4(times[i if contact else i-1]),'slide':r4(distance),'path':r4(path)});start=None
 return {'windows':windows,'worst_slide':r4(worst),'mean_slide':r4(net/contact_time) if contact_time>0 else 0.,'path':r4(total_path),'contact_time':r4(contact_time),'contact_fraction':r4(contact_time)},worst


def knee(times,hips,knees,feet,leg):
 shortest=180.;shortest_at=0.;extension=0.;extension_at=0.;previous=None;flips=0;angle_max=0.;angle_at=0.;valid=0
 for t,hip,k,foot in zip(times,hips,knees,feet):
  upper=sub(hip,k);lower=sub(foot,k)
  if dot(upper,upper)>1e-6 and dot(lower,lower)>1e-6:
   angle=math.degrees(math.acos(max(-1,min(1,dot(unit(upper),unit(lower))))))
   if angle<shortest:shortest=angle;shortest_at=t
  reach=length(sub(hip,foot))/max(leg,.001)
  if reach>extension:extension=reach;extension_at=t
  axis=sub(foot,hip)
  if dot(axis,axis)<1e-6:continue
  axis=unit(axis);bend=sub(k,hip);bend=sub(bend,mul(axis,dot(bend,axis)))
  if length(bend)<max(.02*leg,.001):continue
  pole=unit(bend);valid+=1
  if previous is not None:
   angle=math.degrees(f(math.atan2(length(cross(previous,pole)),dot(previous,pole))))
   if angle>angle_max:angle_max=angle;angle_at=t
   if angle>90:flips+=1
  previous=pole
 return {'min_knee_angle_degrees':r4(shortest),'min_knee_angle_time':r4(shortest_at),'max_extension_ratio':r4(extension),'max_extension_time':r4(extension_at)}, {'flips':flips,'max_angle_degrees':r4(angle_max),'worst_time':r4(angle_at),'valid_samples':valid}


def audit_effect(result,ref):
 if not reference_valid(ref,'motion_audit'):return False
 n=120;times=[i/119 for i in range(n)];frames=[dict(row,points={name:add(point,sub(row['root_sample'],ref['root_start'])) for name,point in row['points'].items()}) for row in ref['frames']];hips=[row['points']['B-hips'] for row in frames];up=ref['up']
 threshold=min(.005,.005*max(ref['legs'].values())/.85)
 heights=[dot(p,up) for p in hips];bob=max(heights)-min(heights);net=flat(hips[0],hips[-1]);path=sum(flat(a,b) for a,b in zip(hips,hips[1:]));in_place=net<.05
 checks={'hip_bob':(bob<=.12,r4(bob),.12)}
 expected_hips={'samples':n,'height_range':r4(bob),'body_travel':r4(net),'body_path':r4(path),'mean_speed':r4(path),'trace':[[r4(x) for x in p] for p in hips]}
 if not equal(result,{'length':1,'loop_mode':'linear','sample_count':n,'contact_threshold':threshold,'motion_kind':'gait','in_place':in_place,'body_travel':r4(net),'undoable':False,'hips':expected_hips}):return False
 foot_points={};ground={}
 for side in ('l','r'):
  suffix=side.upper();name='B-foot.'+suffix;points=[row['points'][name] for row in frames];foot_points[side]=points
  ground[side]=dot(ref['rest_feet'][side],up);leg=ref['legs'][side]
  metrics,worst=slide(times,points,ground[side],threshold)
  depths=[ground[side]-dot(p,up) for p in points];penetration=max(0,max(depths));depth_at=times[depths.index(penetration)] if penetration>0 else 0.
  pose,pole=knee(times,[r['points']['B-thigh.'+suffix] for r in frames],[r['points']['B-shin.'+suffix] for r in frames],points,leg)
  metrics.update(bone=name,ground=r4(ground[side]),max_penetration=r4(penetration),penetration_time=r4(depth_at),penetration_budget=r4(.01*leg),trace=[[r4(x) for x in p] for p in points],pose_range=pose,knee_pole=pole)
  if not equal(result.get('feet',{}).get(side),metrics):return False
  checks['foot_slide.'+side]=(worst<=.05,r4(worst),.05)
  checks['ground_penetration.'+side]=(penetration<=.01*leg,r4(penetration),r4(.01*leg))
  checks['knee_pole_flip.'+side]=(pole['flips']==0,pole['flips'],0)
 counts=dict(l=0,r=0,both=0,flight=0);trace=[];forward_max=lateral_max=0.
 for i,hip in enumerate(hips):
  support=[s for s in ('l','r') if dot(foot_points[s][i],up)-ground[s]<=threshold];state='both' if len(support)==2 else support[0] if support else 'flight';counts[state]+=1
  entry={'time':r4(times[i]),'state':state,'hip_forward':None,'hip_lateral':None}
  if support:
   point=[0.,0.,0.]
   for s in support:point=add(point,foot_points[s][i])
   point=mul(point,1/len(support));offset=sub(hip,point);forward=dot(offset,ref['forward']);lateral=dot(offset,ref['lateral']);forward_max=max(forward_max,abs(forward));lateral_max=max(lateral_max,abs(lateral));entry.update(hip_forward=r4(forward),hip_lateral=r4(lateral))
  trace.append(entry)
 if not equal(result.get('support'),{'sample_count':n,'counts':counts,'trace':trace,'max_abs_hip_forward':r4(forward_max),'max_abs_hip_lateral':r4(lateral_max)}):return False
 grades=result.get('checks',[])
 if len(grades)!=len(checks) or {r.get('check') for r in grades}!=set(checks):return False
 for grade in grades:
  passed,value,budget=checks[grade['check']]
  if not equal(grade,{'passed':passed,'value':value,'budget':budget}):return False
 failed=sum(not row[0] for row in checks.values())
 return equal(result,{'failed_checks':failed,'passed':failed==0})
