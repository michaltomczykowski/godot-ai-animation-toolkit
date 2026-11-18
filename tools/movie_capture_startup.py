"""Run one capture with an exclusively owned pre-startup viewport override.

Usage: --project DIR --width 1400 --height 800 --receipt NEW.json -- godot ...
The command must explicitly name the same --path. Existing overrides are never
replaced. The owned override is removed in finally only if its bytes still match.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(data): return hashlib.sha256(data).hexdigest()


def override_bytes(width,height):
    if width <= 0 or height <= 0: raise ValueError('positive capture dimensions required')
    return ('[display]\nwindow/size/viewport_width=%d\nwindow/size/viewport_height=%d\n'
        'window/size/window_width_override=%d\nwindow/size/window_height_override=%d\n'
        'window/stretch/mode="viewport"\nwindow/stretch/aspect="keep"\n'
        % (width,height,max(1,width//2),max(1,height//2))).encode()


def run_capture(project,width,height,receipt,command,runner=subprocess.run):
    project=Path(project).resolve()
    receipt=Path(receipt)
    command=list(command)
    if not command or '--path' not in command or Path(command[command.index('--path')+1]).resolve()!=project:
        raise ValueError('capture command must explicitly name the same project --path')
    project_file=project/'project.godot'
    before=sha(project_file.read_bytes())
    data=override_bytes(width,height)
    override=project/'override.cfg'
    report={'schema_version':1,'command':command,'project':str(project),'project_sha256_before':before,
        'override_sha256':sha(data),'viewport':[width,height],'window':[max(1,width//2),max(1,height//2)],
        'override_owned':False,'cleanup':'not_created','returncode':None}
    with receipt.open('x',encoding='utf-8') as receipt_stream:
        try:
            with override.open('xb') as stream: stream.write(data)
            report['override_owned']=True
            report['state']='owned_override_ready_before_launch'
            json.dump(report,receipt_stream,indent=2)
            receipt_stream.flush()
            os.fsync(receipt_stream.fileno())
            completed=runner(command,check=False)
            report['returncode']=completed.returncode
        except Exception as exc:
            report['error']=str(exc)
        finally:
            if report['override_owned']:
                if override.is_file() and override.read_bytes()==data:
                    override.unlink()
                    report['cleanup']='owned_override_removed'
                else:
                    report['cleanup']='changed_override_preserved'
                    report['error']='owned override changed during capture; preserved for investigation'
            report['project_sha256_after']=sha(project_file.read_bytes())
            if report['project_sha256_after']!=before: report['error']='project.godot changed during capture'
            report['passed']=report['returncode']==0 and not report.get('error') and report['cleanup']=='owned_override_removed'
            report['state']='finished'
            receipt_stream.seek(0)
            receipt_stream.truncate()
            json.dump(report,receipt_stream,indent=2)
            receipt_stream.flush()
            os.fsync(receipt_stream.fileno())
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path,required=True)
    parser.add_argument('--width',type=int,required=True)
    parser.add_argument('--height',type=int,required=True)
    parser.add_argument('--receipt',type=Path,required=True)
    parser.add_argument('command',nargs=argparse.REMAINDER)
    args=parser.parse_args()
    command=args.command[1:] if args.command[:1]==['--'] else args.command
    result=run_capture(args.project,args.width,args.height,args.receipt,command)
    print('MOVIE_CAPTURE_STARTUP='+json.dumps(result,sort_keys=True))
    raise SystemExit(0 if result['passed'] else 1)
