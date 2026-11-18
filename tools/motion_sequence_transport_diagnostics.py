"""Observe an existing awaited RPC without retries, new RPCs or deadline changes."""
import asyncio
import contextlib
import hashlib
import json
from pathlib import Path
import time


def await_chain(coroutine):
    frames=[]
    for _ in range(24):
        frame=getattr(coroutine,'cr_frame',None) or getattr(coroutine,'gi_frame',None)
        if frame is not None:
            frames.append({'file':frame.f_code.co_filename,'line':frame.f_lineno,'function':frame.f_code.co_name})
        coroutine=getattr(coroutine,'cr_await',None) or getattr(coroutine,'gi_yieldfrom',None)
        if coroutine is None: break
    return frames


async def observed_call(args, client, invoke, name, params, interval=30.0):
    started=time.monotonic()
    record=getattr(args,'record',None)
    path=Path(record).with_suffix('.transport.jsonl') if record else None
    def emit(stage,**values):
        event={'stage':stage,'tool':name,'suite':params.get('suite'),'elapsed_seconds':round(time.monotonic()-started,6),**values}
        line=json.dumps(event,sort_keys=True)
        print('MOTION_SEQUENCE_TRANSPORT='+line,flush=True)
        if path:
            path.parent.mkdir(parents=True,exist_ok=True)
            with path.open('a',encoding='utf-8') as stream:stream.write(line+'\n')
    async def watch():
        while True:
            await asyncio.sleep(interval)
            emit('awaiting',tasks=[{'name':task.get_name(),'done':task.done(),'await_chain':await_chain(task.get_coro())}
                                  for task in list(asyncio.all_tasks())[:32]])
    emit('request_start')
    watcher=asyncio.create_task(watch(),name='motion-sequence-diagnostic-watch')
    try:
        result=await invoke(client,name,params)
        raw=json.dumps(result,sort_keys=True).encode('utf-8')
        emit('response_returned',response_bytes=len(raw),response_sha256=hashlib.sha256(raw).hexdigest(),
             result_type=type(result).__name__)
        return result
    except BaseException as error:
        emit('request_exception',exception_type=type(error).__name__)
        raise
    finally:
        watcher.cancel()
        with contextlib.suppress(asyncio.CancelledError):await watcher
