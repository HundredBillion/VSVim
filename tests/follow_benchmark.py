"""Measure real worker initialization, editor RPC responsiveness and edit latency."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

import pynvim

ROOT = Path(__file__).resolve().parents[1]
NVIM = os.environ.get('VSVIM_NVIM', str(Path.home() / '.local/nvim-nightly/bin/nvim'))
with tempfile.TemporaryDirectory(prefix='follow-benchmark-') as directory:
    project = Path(directory).resolve()
    for index in range(5000):
        folder = project / f'src/{index // 100:03}'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f'{index}.lua').write_text('local value = 1\nreturn value\n')
    subprocess.run(['git', 'init', '-q', str(project)], check=True)
    target = project / 'src/049/4999.lua'
    editor = pynvim.attach('child', argv=[NVIM, '--embed', '--headless', '-u', 'NONE'])
    try:
        editor.exec_lua('vim.opt.runtimepath:prepend(...); require("vsvim.follow").setup()', str(ROOT))
        editor.command('cd ' + editor.funcs.fnameescape(str(project)))
        start = time.monotonic()
        editor.command('VSVimFollowOn')
        samples = []
        while True:
            probe = time.monotonic()
            state = editor.exec_lua('return require("vsvim.follow").status()')
            samples.append((time.monotonic()-probe)*1000)
            if state['ready']:
                break
            assert state['enabled'], state
            assert time.monotonic()-start < 20, state
            time.sleep(.01)
        initialized = (time.monotonic()-start)*1000
        started = time.monotonic()
        target.write_text('local value = 2\nreturn value\n')
        while editor.current.buffer.name != str(target):
            assert time.monotonic()-started < 5, 'external edit timed out'
            time.sleep(.01)
        latency = (time.monotonic()-started)*1000
        assert editor.current.window.cursor == (1, 0)
        assert latency < 1000, latency
        editor.command('VSVimFollowOff')
        assert not editor.exec_lua('return require("vsvim.follow").status().enabled')
        print(json.dumps(dict(files=5000, initialization_ms=round(initialized,1),
                              external_edit_ms=round(latency,1), max_rpc_ms=round(max(samples),1))))
    finally:
        try:
            editor.command('qa!')
        except (EOFError, OSError):
            pass
        editor.close()
