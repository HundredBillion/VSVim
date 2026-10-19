import json,signal,sys,time
from pathlib import Path
import pynvim
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'tests'))
from minimap_benchmark import control,wait_until
meta=json.loads(Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/vsvim-minimap-preview-meta.json').read_text())
root=Path(meta['root']);ctl=Path(meta['control'])
n=pynvim.attach('socket',path=meta['server'])
def watchdog(*_):raise TimeoutError('native input check RPC')
signal.signal(signal.SIGALRM,watchdog)
def mode():
 signal.alarm(5)
 value=n.api.get_mode()
 signal.alarm(0)
 return value
def action(*events):control(ctl,list(events))
def key(text,code,**kw):action(dict(type='key',text=text,code=code,**kw))
original=n.current.buffer.number
probe=original
saved_lines=n.api.buf_get_lines(original,0,-1,True)
saved_modified=n.api.get_option_value("modified",{"buf":original})
result={}
try:
 n.input("<Esc>")
 wait_until(lambda:mode()["mode"]=="n",10)
 action({"type":"activate"},{"type":"down","x":200,"y":120},{"type":"up","x":200,"y":120})
 n.input("<Esc>")
 wait_until(lambda:mode()["mode"]=="n",10)
 n.api.win_set_cursor(0,[1,0])
 n.api.buf_set_lines(probe,0,-1,True,['word first line']+[f'row {i} word' for i in range(2,1001)])
 n.api.win_set_buf(0,probe)
 wait_until(lambda:(lambda t: t and t.get('buffer')==probe and t.get('total')==1000 and t.get('generation') and not t.get('busy'))(n.exec_lua("return require('vsvim.minimap').provider().target()")),20)
 key('v',9);wait_until(lambda:mode()['mode']=='v',10)
 key('r',15);wait_until(lambda:mode()['blocking'],10)
 key('x',7);wait_until(lambda:mode()['mode']=='n' and not mode()['blocking'],10)
 assert n.api.buf_get_lines(probe,0,1,True)==['xord first line']
 result['fragmented_native_visual_replace']='pass: xord first line'
 n.api.buf_set_lines(probe,0,1,True,['word first line'])
 n.exec_lua("_G.input_probe_old_clipboard=vim.g.clipboard;_G.input_probe_clip={{},'v'};local function copy(lines,kind) _G.input_probe_clip={lines,kind} end;vim.g.clipboard={name='input bridge test',cache_enabled=0,copy={['+']=copy,['*']=copy},paste={['+']=function() return _G.input_probe_clip end,['*']=function() return _G.input_probe_clip end}};vim.fn['provider#clipboard#Executable']()")
 n.command('normal! gg0v3l')
 metadata=root/'input-window.json';action({'type':'metadata','path':str(metadata)})
 win=json.loads(metadata.read_text());x=win['width']-80;y=win['height']*.75
 action({'type':'down','x':x,'y':y},{'type':'up','x':x,'y':y})
 wait_until(lambda:n.funcs.line('w0')>100,10)
 key('c',8,cmd=True)
 wait_until(lambda:n.exec_lua('return _G.input_probe_clip[1]')==['word'],10)
 assert n.funcs.mode()=='v'
 result['native_cmd_c_after_minimap_browse']='pass: original word copied once'
 result['pass']=True
finally:
 signal.alarm(0)
 key('\x1b',53)
 n.exec_lua("vim.g.clipboard=_G.input_probe_old_clipboard;_G.input_probe_old_clipboard=nil;_G.input_probe_clip=nil;vim.fn['provider#clipboard#Executable']()")
 n.api.win_set_buf(0,original)
 n.api.buf_set_lines(probe,0,-1,True,saved_lines)
 n.api.set_option_value('modified',saved_modified,{'buf':probe})
 n.command('normal! gg0')
 action({'type':'activate'})
 n.close()
 (root/'input-bridge-native-check.json').write_text(json.dumps(result,indent=2))
 print(json.dumps(result))
