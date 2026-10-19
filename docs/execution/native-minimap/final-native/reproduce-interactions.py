import json,time,subprocess,os,sys
from pathlib import Path
import pynvim
sys.path.insert(0,'/Users/davidlee/Projects/VSVim/tests')
from minimap_benchmark import control,wait_until,events,revision
meta=json.loads(Path('/tmp/vsvim-minimap-live-meta.json').read_text());root=Path(meta['root']);ctl=Path(meta['control']);native=root/'native.jsonl'
n=pynvim.attach('socket',path=meta['server']);result={'meta':meta,'revisions':{x:revision(Path('/Users/davidlee/Projects')/x) for x in ['VSVim','sprite.nvim','Sprite']},'cases':{}}
def target():return n.exec_lua("return require('vsvim.minimap').provider().target()")
def stable():
 t=wait_until(lambda:(lambda t:t if t and t.get('generation') and not t.get('busy') else None)(target()),90)
 wait_until(lambda:next((e for e in reversed(events(native)) if e['event']=='paint' and e['generation']==t['generation']),None),20);return t
def action(*a):control(ctl,list(a))
def capture(name):
 p=root/('final3-'+name+'.png');action({'type':'capture','path':str(p)});wait_until(p.exists,10);return str(p)
def state():return n.exec_lua("return {mode=vim.fn.mode(),cursor=vim.api.nvim_win_get_cursor(0),top=vim.fn.line('w0'),bottom=vim.fn.line('w$'),selection=require('vsvim.minimap.selection').state(vim.api.nvim_get_current_win())}")
def key(text,code,**kw):action(dict(type='key',text=text,code=code,**kw))
def normal(cmd):n.command('normal! '+cmd);n.command('redraw!');time.sleep(.15)
def metadata():
 p=root/'window.json';action({'type':'metadata','path':str(p)});return json.loads(p.read_text())
try:
 stable();action({'type':'resize','width':937,'height':720});time.sleep(.3);win=metadata();result['window']=win;w=win['width'];h=win['height'];x=w-80
 # Real unsaved HEAD hunk, easily hit visible word and several other occurrences.
 n.api.buf_set_lines(0,0,1,True,['file = "file"']);stable();normal('gg0')
 wait_until(lambda:next((e for e in reversed(events(native)) if e['event']=='paint' and e.get('first_line_change')),None),10)
 result['cases']['initial']={'target':target(),'screenshot':capture('current-native-code-git')}
 action({'type':'down','x':57,'y':92,'count':2},{'type':'up','x':57,'y':92,'count':2});time.sleep(.25)
 s=state();assert s['mode'] in ['v','V'],s;assert s['selection']['word']=='file',s
 result['cases']['word-overlap']={'state':s,'screenshot':capture('current-native-word-git-overlap')}
 key('\x1b',53);normal('13ggV14j');result['cases']['selected-rows']={'state':state(),'screenshot':capture('current-native-selected-rows')}
 key('\x1b',53);n.exec_lua("require('vsvim.sidebar').explorer(...)",meta['repo']);time.sleep(1);result['cases']['narrow']={'window':metadata(),'uis':n.api.list_uis(),'method':'supported native SVGTree dock reduces editor surface width','screenshot':capture('current-native-narrow')}
 n.exec_lua("require('vsvim.sidebar').explorer(...)",meta['repo']);time.sleep(.5)
 action({'type':'resize','width':937,'height':720});n.command('set background=light');n.command('colorscheme default');stable();time.sleep(.3);result['cases']['light']={'screenshot':capture('current-native-light')}
 n.command('set background=dark');n.command('colorscheme default');stable()
 n.exec_lua("_G.test_clipboard={{},'v'};local function copy(lines,kind) _G.test_clipboard={lines,kind} end;local function paste() return _G.test_clipboard end;vim.g.clipboard={name='isolated native evidence',cache_enabled=0,copy={['+']=copy,['*']=copy},paste={['+']=paste,['*']=paste}};vim.fn['provider#clipboard#Executable']()")
 first=n.api.buf_get_lines(0,0,3,True);normal('ggV2j');action({'type':'down','x':x,'y':h*.75},{'type':'up','x':x,'y':h*.75});time.sleep(.3)
 s=state();assert s['top']>100 and s['selection']['selection']==[1,3],s
 key('c',8,cmd=True);clip=wait_until(lambda:(lambda v:v if v[0] else None)(n.exec_lua('return _G.test_clipboard')),5);assert clip==[first+[''],'V'],(clip,first)
 result['cases']['preserved-native-copy']={'state':s,'clipboard':clip,'provider':'isolated in-memory, no system clipboard access','screenshot':capture('current-native-preserved-copy')}
 key('\x1b',53);normal('ggV2j');action({'type':'down','x':x,'y':h*.75},{'type':'up','x':x,'y':h*.75});time.sleep(.2);old=n.api.buf_get_lines(0,0,-1,True);key('x',7);wait_until(lambda:n.api.buf_line_count(0)==len(old)-3,10);assert n.api.buf_get_lines(0,0,1,True)==old[3:4]
 result['cases']['edit-after-browse']={'removed_rows':3,'actual_first_line':n.api.buf_get_lines(0,0,1,True),'expected_first_line':old[3:4]}
 long=Path(meta['repo'])/'long.lua';lines=['local values = {}','local function transform(value) return value * 2 end']+[f'values[{i}] = transform({i})' for i in range(3,100000)]+['return values'];long.write_text('\n'.join(lines)+'\n')
 subprocess.run(['git','add','long.lua'],cwd=meta['repo'],check=True);subprocess.run(['git','-c','user.name=VSVim Test','-c','user.email=test@example.invalid','commit','--allow-empty','-qm','Long native drag fixture'],cwd=meta['repo'],check=True)
 n.command('edit! '+str(long));stable();normal('gg');action({'type':'down','x':x,'y':72},{'type':'drag','x':x,'y':h+40});time.sleep(.4);s=state();assert s['bottom']==100000,s;result['cases']['long-bottom']={'state':s,'screenshot':capture('current-native-long-bottom')}
 action({'type':'drag','x':x,'y':0});time.sleep(.4);s=state();assert s['top']==1,s;result['cases']['long-top']={'state':s,'screenshot':capture('current-native-long-top')};action({'type':'up','x':x,'y':0})
 result['pass']=True
finally:
 (root/'final3-interactions.json').write_text(json.dumps(result,indent=2));print(json.dumps({'root':str(root),'cases':list(result['cases']),'pass':result.get('pass',False)}),flush=True)
 n.request('nvim_command','qa!',async_=True)
 n.close()
 time.sleep(.5)
 import signal
 try:os.killpg(meta['pid'],signal.SIGTERM)
 except ProcessLookupError:pass
