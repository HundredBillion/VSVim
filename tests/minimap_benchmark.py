"""Isolated macOS native minimap measurements; JSON lines, with honest budget verdicts.

Build Sprite with `cargo build -p sprite-app --bin sprite --features minimap-benchmark --locked`.
Run `uv run --with pynvim python tests/minimap_benchmark.py --output /tmp/minimap-evidence`.
The helper captures and sends events only to the new test process's own window.
"""
import argparse
import ctypes
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time

import pynvim

ROOT = Path(__file__).resolve().parents[1]


def percentile(values, fraction=.95):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def wait_until(predicate, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.005)
    raise TimeoutError('native benchmark condition')


def revision(path):
    return subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()


def events(path):
    try:
        return [json.loads(line) for line in path.read_text().split('\n')[:-1] if line]
    except FileNotFoundError:
        return []


def control(path, actions):
    Path(str(path) + '.done').unlink(missing_ok=True)
    draft = path.with_suffix('.new')
    draft.write_text(json.dumps(actions))
    draft.replace(path)
    wait_until(lambda: path.with_suffix('.json.done').exists() or Path(str(path) + '.done').exists(), 10)


class TaskInfo(ctypes.Structure):
    _fields_ = [('virtual_bytes', ctypes.c_uint64), ('resident_bytes', ctypes.c_uint64)] + [
        (f'time_{i}', ctypes.c_uint64) for i in range(4)] + [
        (f'counter_{i}', ctypes.c_int32) for i in range(12)]


LIBPROC = ctypes.CDLL('/usr/lib/libproc.dylib')
LIBPROC.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
LIBPROC.proc_listchildpids.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
LIBPROC.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]


def process_rss(pid):
    info = TaskInfo()
    size = ctypes.sizeof(info)
    return info.resident_bytes // 1024 if LIBPROC.proc_pidinfo(pid, 4, 0, ctypes.byref(info), size) == size else None


def nvim_children(pid):
    children = (ctypes.c_int * 256)()
    size = LIBPROC.proc_listchildpids(pid, children, ctypes.sizeof(children))
    result = []
    for child in children[:max(0, size) // ctypes.sizeof(ctypes.c_int)]:
        path = ctypes.create_string_buffer(4096)
        if LIBPROC.proc_pidpath(child, path, len(path)) > 0 and Path(os.fsdecode(path.value)).name == 'nvim':
            result.append(child)
    return result


def edited_band_paint(event, previous_generation, edit_start):
    return (event['event'] == 'paint' and event['unix_ns'] > edit_start
            and event['generation'] != previous_generation and event.get('first_line_change') is True)


def run_case(args, count, plugins, helper):
    folder = args.output / str(count)
    folder.mkdir(parents=True)
    project = folder / 'project'
    project.mkdir()
    lines = ['local values = {}', 'local function transform(value) return value * 2 end']
    lines += [f'values[{i}] = transform({i})' for i in range(3, count)]
    lines += ['return values']
    fixture = project / 'fixture.lua'
    fixture.write_text('\n'.join(lines) + '\n')
    def git(*words):
        subprocess.run(['git', '-C', str(project), *words], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    git('init', '-q')
    git('add', 'fixture.lua')
    git('-c', 'user.name=VSVim Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')
    lines[20] += ' -- changed against HEAD'
    lines[80:80] = ['-- native minimap added band']
    del lines[-2]
    fixture.write_text('\n'.join(lines) + '\n')
    data = folder / 'data/vsvim'
    data.mkdir(parents=True)
    shutil.copytree(plugins, data / 'lazy', symlinks=True)
    subprocess.run(['/bin/cp','-cR',str(args.plugin_cache.parent / 'mason'),str(data / 'mason')],check=True)
    socket = folder / 'editor.sock'
    controls = folder / 'control.json'
    native_log = folder / 'native.jsonl'
    env = dict(os.environ, NVIM_APPNAME='vsvim', VSVIM_ROOT=str(ROOT), VSVIM_NVIM=args.nvim,
               DYLD_INSERT_LIBRARIES=str(helper), VSVIM_CONTROL_PATH=str(controls),
               SPRITE_MINIMAP_BENCHMARK_LOG=str(native_log))
    for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
        env[f'XDG_{kind}_HOME'] = str(folder / kind.lower())
    profile = ROOT / 'tests/helpers/minimap_profile.lua'
    cmd = [str(args.sprite), '--config', str(ROOT / 'extras/sprite-jb.toml'), '-e', args.nvim,
           '-l', str(args.adapter / 'lua/sprite/adapter.lua'), '--cmd', f"lua dofile('{profile}')",
           '-u', str(ROOT / 'init.lua'), '--cmd', 'let g:vsvim_auto_explorer = v:false',
           '--listen', str(socket), str(fixture)]
    process_log = (folder / 'sprite.log').open('w')
    process = subprocess.Popen(cmd, cwd=project, env=env, stdout=process_log, stderr=process_log, start_new_session=True)
    nvim = None
    peak = {'host_kib': 0, 'editor_kib': 0}
    stop = threading.Event()
    heartbeat_stop = threading.Event()
    heartbeat_samples=[]
    heartbeat_thread=None
    def memory():
        while not stop.wait(.1):
            pids = [str(process.pid)]
            editor = peak.get('editor_pid')
            if editor:
                pids.append(str(editor))
            if editor:
                for child in nvim_children(editor):
                    peak['worker_pid'] = child
                    peak.setdefault('worker_pids', [])
                    if child not in peak['worker_pids']: peak['worker_pids'].append(child)
                    pids.append(str(child))
            for pid in map(int,pids):
                rss = process_rss(pid)
                if rss is not None:
                    key = 'host_kib' if pid == process.pid else 'editor_kib' if pid == editor else 'worker_kib'
                    peak[key] = max(peak.get(key,0),rss)
    thread = threading.Thread(target=memory, daemon=True)
    thread.start()
    try:
        wait_until(lambda: socket.exists() or process.poll() is not None)
        if process.poll() is not None:
            raise RuntimeError((folder / 'sprite.log').read_text())
        nvim = pynvim.attach('socket', path=str(socket))
        peak['editor_pid'] = nvim.eval('getpid()')
        def heartbeat():
            connection=pynvim.attach('socket',path=str(socket))
            try:
                while not heartbeat_stop.is_set():
                    started=time.monotonic_ns()
                    value=connection.exec_lua("return require('vsvim.minimap.worker').status()")
                    heartbeat_samples.append((time.monotonic_ns()-started)/1e6)
                    if value:
                        peak['worker_pid']=value['pid']
                    heartbeat_stop.wait(.05)
            finally:
                connection.close()
        heartbeat_thread=threading.Thread(target=heartbeat,daemon=True)
        heartbeat_thread.start()
        first = wait_until(lambda: next((e for e in events(native_log) if e['event'] == 'paint'), None))
        heartbeat_stop.set()
        heartbeat_thread.join(timeout=5)
        wait_until(lambda: nvim.exec_lua("local t=require('vsvim.minimap').provider().target();return t and not t.busy"))
        control(controls,[dict(type='resize',width=960,height=672)])
        time.sleep(.15)
        cold_metrics = nvim.exec_lua('return minimap_metrics')
        (folder / 'startup-metrics.json').write_text(json.dumps(cold_metrics, indent=2))
        def sync_result(metrics, paint, label):
            source = next(x for x in metrics['source'] if x.get('ms') is not None)
            commit = next(x for x in metrics['ops'] if x['kind'] == 'commit')
            return dict(cache=label, source_ms=source['ms'],
                        complete_source_sync_ms=(commit['unix_ns'] - source['unix_ns']) / 1e6,
                        first_painted_content_ms=(paint['unix_ns'] - source['unix_ns']) / 1e6)
        cold = sync_result(cold_metrics, first, 'process-cold; OS caches uncontrolled')
        nvim.exec_lua('minimap_metrics.source={};minimap_metrics.ops={};minimap_metrics.callbacks={}')
        before = time.time_ns()
        nvim.command('VSVimMinimapToggle | VSVimMinimapToggle')
        warm_paint = wait_until(lambda: next((e for e in events(native_log) if e['event'] == 'paint' and e['unix_ns'] > before and e['generation'] != first['generation']), None))
        wait_until(lambda: nvim.exec_lua("local t=require('vsvim.minimap').provider().target();return t and not t.busy"))
        warm_metrics = nvim.exec_lua('return minimap_metrics')
        warm = sync_result(warm_metrics, warm_paint, 'same-process warm')
        time.sleep(.25)
        control(controls, [dict(type='capture', path=str(folder / 'before-scroll.png'))])
        wait_until(lambda: (folder / 'before-scroll.png').exists(), 10)
        if args.focus:
            control(controls,[dict(type='activate')])
            time.sleep(.1)
        control(controls,[dict(type='metadata',path=str(folder / 'window.json'))])
        wait_until(lambda: (folder / 'window.json').exists(),10)
        window_info=json.loads((folder / 'window.json').read_text())
        quiet_observations=[]
        quiet_since=None
        quiet_deadline=time.monotonic()+30
        quiet=False
        while time.monotonic()<quiet_deadline:
            state=nvim.exec_lua("local clients={};for _,client in ipairs(vim.lsp.get_clients({bufnr=0})) do clients[#clients+1]={name=client.name,initialized=client.initialized} end;return {status=vim.lsp.status(),clients=clients,diagnostics=#vim.diagnostic.get(0)}")
            quiet_observations.append(state)
            ready=state['status']=='' and all(client['initialized'] for client in state['clients'])
            if ready and (len(quiet_observations)==1 or state['diagnostics']==quiet_observations[-2]['diagnostics']):
                quiet_since=quiet_since or time.monotonic()
                if time.monotonic()-quiet_since>=1:
                    quiet=True
                    break
            else:
                quiet_since=None
            time.sleep(.05)
        def scroll_pass():
            scroll=[]
            for i in range(args.samples):
                previous = [e for e in events(native_log) if e['event'] == 'paint'][-1]['viewport']
                after = time.time_ns()
                control(controls, [dict(type='wheel', x=window_info['width']-80, y=min(300,window_info['height']/2), dy=-60)])
                sent = wait_until(lambda: next((e for e in events(native_log) if e['event'] == 'input' and e['kind'] == 'wheel' and e['unix_ns'] > after), None), 10)
                frame = wait_until(lambda: next((e for e in events(native_log) if e['event'] == 'paint' and e['unix_ns'] > sent['unix_ns'] and e['viewport'] != previous), None), 10)
                scroll.append(dict(input_ns=sent['unix_ns'], paint_ns=frame['unix_ns'], ms=(frame['unix_ns']-sent['unix_ns'])/1e6))
            return scroll
        prewarm=scroll_pass()
        nvim.command('normal! gg')
        nvim.command('redraw!')
        wait_until(lambda: [e for e in events(native_log) if e['event']=='paint'][-1]['viewport'][0]==1,10)
        time.sleep(.2)
        sample_start = time.time_ns()
        scroll=scroll_pass()
        scroll_end = time.time_ns()
        if args.focus:
            control(controls,[dict(type='restore-front')])
        scroll_metrics = nvim.exec_lua('return minimap_metrics')
        scroll_ops = [o for o in scroll_metrics['ops'] if sample_start <= o['unix_ns'] <= scroll_end]
        nvim.command('normal! gg')
        nvim.command('redraw!')
        time.sleep(.1)
        previous_generation = nvim.exec_lua("return require('vsvim.minimap').provider().target().generation")
        edit_start = time.time_ns()
        nvim.api.buf_set_lines(0, 0, 1, False, ['local values = {} -- unsaved benchmark edit'])
        updated = wait_until(lambda: next((e for e in events(native_log) if edited_band_paint(e,previous_generation,edit_start)), None))
        source_paint=next(e for e in events(native_log) if e['event']=='paint' and e['unix_ns']>edit_start and e['generation']!=previous_generation)
        time.sleep(.1)
        final_metrics = nvim.exec_lua('return minimap_metrics')
        control(controls, [dict(type='capture', path=str(folder / 'native.png'))])
        wait_until(lambda: (folder / 'native.png').exists(), 10)
        paints = [e['ms'] for e in events(native_log) if e['event'] == 'paint' and sample_start <= e['unix_ns'] <= scroll_end]
        chunks = [o['bytes'] for o in cold_metrics['ops'] + final_metrics['ops'] if o['kind'] == 'lines']
        callbacks = [value for phase in (cold_metrics, final_metrics) for key,value in phase['callbacks'].items() if '/vsvim/minimap/' in key or '/vsvim/minimap.lua:' in key]
        callback_max = max([x['max_ms'] for x in callbacks] + [cold_metrics.get('receive_max_ms',0), final_metrics.get('receive_max_ms',0)])
        metrics = dict(lines=count, revisions=dict(vsvim=revision(ROOT), adapter=revision(args.adapter), host=revision(args.sprite_repo)),
                       samples=dict(initial_cold=1, initial_warm=1, prewarm_scroll=args.samples, scroll=args.samples, paint=len(paints), edit=1),
                       analysis_quiet=dict(reached=quiet,timeout_seconds=30,quiet_seconds=1,observations=quiet_observations),
                       prewarm_scroll_input_to_paint_ms=dict(p95=percentile([x['ms'] for x in prewarm]),raw=prewarm),
                       display_scale=first['scale'], window=json.loads((folder / 'window.json').read_text()), initial=dict(cold=cold, warm=warm),
                       scroll_input_to_paint_ms=dict(p95=percentile([x['ms'] for x in scroll]), raw=scroll),
                       warm_native_paint_ms=dict(p95=percentile(paints), raw=paints),
                       edit_to_updated_band_ms=(updated['unix_ns']-edit_start)/1e6,
                       edit_source_repaint_ms=(source_paint['unix_ns']-edit_start)/1e6,
                       edit_expected_band=dict(start=1,kind='modified',paint=updated),
                       scheduled_callback_max_ms=callback_max,
                       query_config=nvim.exec_lua("return require('vsvim.minimap.query_config').status()"),
                       worker=nvim.exec_lua("return require('vsvim.minimap.worker').status()"),
                       dependency_state='copied installed Mason packages; no user installation changed',
                       source_chunk_max_bytes=max(chunks), source_bytes=sum(chunks),
                       pure_scroll_source_messages=sum(o['kind'] in ('begin','lines','commit') for o in scroll_ops),
                       pure_scroll_state_messages=sum(o['kind'] == 'state' for o in scroll_ops), peak_rss=peak,
                       initial_rpc_heartbeat_ms=dict(samples=len(heartbeat_samples),max=max(heartbeat_samples),p95=percentile(heartbeat_samples),raw=heartbeat_samples),
                       memory_sampling_ms=100, memory_sampling_method='macOS libproc TASKINFO and owned-child discovery; no subprocesses',
                       measurement='CPU canvas paint submission end; not GPU presentation/compositor timestamp')
        initial_budget = {1000:500, 10000:2000, 100000:10000}[count]
        metrics['acceptance'] = dict(analysis_quiet=quiet, editor_slices=metrics['scheduled_callback_max_ms'] <= 4,
                                    source_chunks=metrics['source_chunk_max_bytes'] <= 256*1024,
                                    scroll_no_source=metrics['pure_scroll_source_messages'] == 0,
                                    native_paint=metrics['warm_native_paint_ms']['p95'] <= 8,
                                    scroll_latency=metrics['scroll_input_to_paint_ms']['p95'] <= 33,
                                    initial_cold=cold['first_painted_content_ms'] <= initial_budget,
                                    initial_warm=warm['first_painted_content_ms'] <= initial_budget,
                                    edit=metrics['edit_to_updated_band_ms'] <= (1000 if count == 100000 else 250))
        (folder / 'editor-metrics.json').write_text(json.dumps(dict(cold=cold_metrics, warm=warm_metrics, final=final_metrics), indent=2))
        (folder / 'result.json').write_text(json.dumps(metrics, indent=2))
        print(json.dumps(metrics), flush=True)
    finally:
        stop.set()
        heartbeat_stop.set()
        if heartbeat_thread:
            heartbeat_thread.join(timeout=2)
        thread.join(timeout=2)
        if nvim:
            if args.focus:
                control(controls,[dict(type='restore-front')])
            diagnostics=nvim.exec_lua("return {metrics=minimap_metrics,messages=vim.fn.execute('messages'),target=require('vsvim.minimap').provider().target(),query=require('vsvim.minimap.query_config').status(),worker=require('vsvim.minimap.worker').status()}")
            (folder / 'diagnostics.json').write_text(json.dumps(diagnostics,indent=2))
            control(controls,[dict(type='capture',path=str(folder / 'final.png'))])
            try:
                nvim.command('qa!')
            except (EOFError, OSError):
                pass
            nvim.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=5)
        process_log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--lines', type=int, nargs='+', default=[1000, 10000, 100000], choices=[1000,10000,100000])
    parser.add_argument('--samples', type=int, default=30)
    parser.add_argument('--focus',action='store_true',help='activate only the owned fixture during scroll samples, then restore previous front app')
    parser.add_argument('--nvim', default=os.environ.get('VSVIM_NVIM', '/Users/davidlee/.local/nvim-nightly/bin/nvim'))
    parser.add_argument('--sprite-repo', type=Path, default=ROOT.parent / 'Sprite')
    parser.add_argument('--sprite', type=Path, default=ROOT.parent / 'Sprite/target/debug/sprite')
    parser.add_argument('--adapter', type=Path, default=ROOT.parent / 'sprite.nvim')
    parser.add_argument('--plugin-cache', type=Path, default=Path.home() / '.local/share/vsvim/lazy')
    args = parser.parse_args()
    if args.samples < 30:
        parser.error('at least 30 warm scroll samples required')
    args.output = args.output.resolve()
    args.output.mkdir(parents=True)
    helper = args.output / 'native-control.dylib'
    subprocess.run(['clang', '-dynamiclib', '-fobjc-arc', '-framework', 'AppKit', '-framework', 'ScreenCaptureKit', '-framework', 'ImageIO', str(ROOT / 'tests/helpers/minimap_native_control.m'), '-o', str(helper)], check=True, capture_output=True)
    with tempfile.TemporaryDirectory(prefix='vsvim-mm-plugins-') as temp:
        plugins = Path(temp)
        for name in ('lazy.nvim', 'nvim-lspconfig', 'mason.nvim', 'mason-lspconfig.nvim', 'sprite.nvim', 'svgtree.nvim', 'scm.nvim'):
            source = args.adapter if name == 'sprite.nvim' else args.plugin_cache / name
            shutil.copytree(source, plugins / name, ignore=shutil.ignore_patterns('.git', 'target'))
        for count in args.lines:
            run_case(args, count, plugins, helper)


if __name__ == '__main__':
    main()
