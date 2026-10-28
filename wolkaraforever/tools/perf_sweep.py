#!/usr/bin/env python3
"""Measure frame pacing on the device across graphics settings, and keep the numbers.

Why this exists: `docs/PERFORMANCE_LANES.md` could say what the login screen and a
cinematic did at one setting, once, by hand. The question this tool answers is a
comparison - which setting holds a frame under the display budget, and what the same
scene costs once the SoC throttles - so the settings have to be swept and the numbers
have to be kept.

What it measures: the client's own frame-timing line, which `--measure-native` writes
once every five seconds (platform/translation/Metal/Presentation.m, layer patches 0019
and 0026):

    frame timing seconds=5.01 fps=60.0 gap_avg_ms=16.67 max_gap_ms=25.0
      ... gpu_ms=8.1 gpu_load=0.53 wait_ms=0.01 cpu_submit_avg_ms=0.04
      ... thermal=2

`thermal` is `ProcessInfo.thermalState`: 0 nominal, 1 fair, 2 serious, 3 critical.
`gpu_ms` is the GPU's own time for the presented frame; a GPU-bound frame has it close
to the frame interval, a CPU-bound or vsync-pinned frame has it well below.

Each variant is a set of CVars written into the client's own `Config.wtf` before the
client starts, because the client reads them only at start. They are the same names
the app itself will write (`product` CVar allowlist in wolkaraforever/WoW/ForeverUI.m).

    renderScale         internal render resolution, 1.0 is native (2732x2048 here)
    gxForegroundFPS     frame cap while the game is in front; 0 or absent is no cap
    gxBackgroundFPS     frame cap while it is not
    vsync               1 presents in step with the display

usage:
    wolkaraforever/tools/perf_sweep.py --stop-first --variants native,preset,half
    wolkaraforever/tools/perf_sweep.py --stop-first --variants stress --seconds 900
    wolkaraforever/tools/perf_sweep.py --stop-first --variants preset --hot

    --variants A,B,...   named variants (see VARIANTS) or `name:key=value;key=value`
    --seconds N          steady-state sampling time per variant (default 60 s)
    --settle N           extra wait after the first frame before sampling (default 20 s)
    --stop-first         stop a running session first; without it the tool refuses,
                         because a live session is not ours to take away
    --hot                keep one long run going: sample every --seconds instead of
                         stopping, so a thermal ramp can be watched in one session
    --device UDID        override DEVICE
    --bundle ID          override TOLKARA_BUNDLE_ID

It writes one CSV and one markdown summary under logs/perf/<timestamp>/, prints the
summary, and fails when a variant produced no windows - a run that did not start is
not a measurement.
"""
import argparse
import datetime
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
GAME = 'Documents/World of Warcraft/_forever_'
CONFIG = GAME + '/WTF/Config.wtf'
GUEST_LOG = 'Documents/native-guest.log'
ERRORS = GAME + '/Errors'
THERMAL = {0: 'nominal', 1: 'fair', 2: 'serious', 3: 'critical'}
DEVICE = ''
BUNDLE = ''

# The variants worth measuring, and why each exists.
VARIANTS = {
    # What the client does out of the box here: native scale, no frame cap.
    'native': {'renderScale': '1.0'},
    # What the app's own preset writes (ForeverUI +performancePreset).
    'preset': {'renderScale': '0.75', 'gxForegroundFPS': '60', 'gxBackgroundFPS': '30', 'vsync': '1'},
    # Half scale: the next step down if 0.75 does not hold a frame when throttled.
    'half': {'renderScale': '0.5', 'gxForegroundFPS': '60', 'gxBackgroundFPS': '30', 'vsync': '1'},
    # Native scale without the 60 cap: the "never render faster than the panel"
    # question, isolated from resolution.
    'uncapped': {'renderScale': '1.0', 'gxForegroundFPS': '0', 'vsync': '1'},
    # Deliberately more GPU work than the panel needs, to drive the SoC into
    # throttle on a scene that can be reproduced without logging in. No frame cap
    # is set here: `gxForegroundFPS 0` reads as a cap of zero in this client and
    # stops it presenting frames at all (measured 2026-10-27), so a variant that
    # wants no cap must simply not name a cap.
    'stress': {'renderScale': '2.0', 'vsync': '1'},
}


def die(message):
    print(f'perf_sweep: {message}', file=sys.stderr)
    sys.exit(2)


def load_env():
    values = {}
    local = ROOT / 'local.env'
    if local.is_file():
        for line in local.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, _, value = line.partition('=')
            values[key.strip()] = value.strip().strip('"')
    return values


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def devicectl(*args, check=False):
    result = run(['xcrun', 'devicectl', *args])
    if check and result.returncode:
        die(f'devicectl {" ".join(args)} failed: {result.stderr.strip() or result.stdout.strip()}')
    return result


def pull(remote, local, domain, bundle, device):
    Path(local).parent.mkdir(parents=True, exist_ok=True)
    return devicectl('device', 'copy', 'from', '--device', device, '--domain-type', 'appDataContainer',
                     '--domain-identifier', bundle, '--source', remote, '--destination', str(local))


def pull_log(local):
    """Pull the guest log, retrying, and never replace a good log with an empty one.

    A `devicectl copy from` that fails (the device is busy, or CoreDevice times out)
    can still leave a zero-byte destination behind. That is how one variant's windows
    went missing after they had already been read successfully.
    """
    local = Path(local)
    staged = local.with_suffix(local.suffix + '.new')
    for attempt in range(3):
        staged.unlink(missing_ok=True)
        pull(GUEST_LOG, staged, 'appDataContainer', BUNDLE, DEVICE)
        if staged.is_file() and staged.stat().st_size > 0:
            staged.replace(local)
            return local
        time.sleep(3)
    return local if local.is_file() else None


def push(local, remote, bundle, device):
    return devicectl('device', 'copy', 'to', '--device', device, '--domain-type', 'appDataContainer',
                     '--domain-identifier', bundle, '--source', str(local), '--destination', remote)


def app_pid(device, bundle):
    """The pid of this bundle's installed executable, or ''. Same idea as running_app.sh."""
    listing = devicectl('device', 'info', 'processes', '--device', device)
    for line in listing.stdout.splitlines():
        if '/Tolkara.app/Tolkara' in line and '/PlugIns/' not in line:
            parts = line.split()
            if parts and parts[0].isdigit():
                return parts[0]
    return ''


def stop_app(device, bundle, say):
    pid = app_pid(device, bundle)
    if not pid:
        say('  nothing running')
        return
    say(f'  stopping pid {pid}: SIGTERM, then SIGKILL if it ignores it')
    devicectl('device', 'process', 'signal', '--device', device, '--pid', pid, '--signal', 'SIGTERM')
    for _ in range(4):
        time.sleep(2)
        if not app_pid(device, bundle):
            return
    pid = app_pid(device, bundle)
    if pid:
        devicectl('device', 'process', 'signal', '--device', device, '--pid', pid, '--signal', 'SIGKILL')
        for _ in range(5):
            time.sleep(2)
            if not app_pid(device, bundle):
                return
    die('the app would not stop; nothing was measured')


def set_cvars(text, values):
    """Set each `SET key "value"` in place, or append it. A value of None removes it."""
    lines, seen = [], set()
    for line in text.splitlines():
        match = re.match(r'\s*SET\s+([A-Za-z0-9_]+)\s+"(.*)"\s*$', line)
        if match and match.group(1) in values:
            key = match.group(1)
            if key in seen:
                continue
            seen.add(key)
            if values[key] is not None:
                lines.append(f'SET {key} "{values[key]}"')
            continue
        lines.append(line)
    for key, value in values.items():
        if key not in seen and value is not None:
            lines.append(f'SET {key} "{value}"')
    return '\n'.join(lines) + '\n'


FIELD = re.compile(r'(\w+)=([-\w.]+)')


def windows(log_path):
    """The frame-timing lines of one run, as dicts of numbers."""
    rows = []
    if not Path(log_path).is_file():
        return rows
    for line in Path(log_path).read_text(errors='replace').splitlines():
        if 'frame timing' not in line:
            continue
        row = {}
        for key, value in FIELD.findall(line.split('frame timing', 1)[1]):
            try:
                row[key] = float(value)
            except ValueError:
                row[key] = value
        if 'fps' in row:
            rows.append(row)
    return rows


def summarise(rows):
    if not rows:
        return None
    def column(name):
        return [row[name] for row in rows if name in row]
    fps = column('fps')
    gpu = column('gpu_ms')
    gaps = column('max_gap_ms')
    load = column('gpu_load')
    wait = column('wait_ms')
    thermal = [int(row.get('thermal', -1)) for row in rows]
    gaps.sort()
    def mean(values):
        return sum(values) / len(values) if values else float('nan')
    return {
        'windows': len(rows),
        'fps_mean': mean(fps),
        'fps_min': min(fps),
        'fps_max': max(fps),
        'at_60': sum(1 for value in fps if value >= 59.5) / len(fps),
        'gpu_ms_mean': mean(gpu),
        'gpu_load_mean': mean(load),
        'wait_ms_mean': mean(wait),
        'gap_p95': gaps[max(0, int(round(0.95 * (len(gaps) - 1))))] if gaps else float('nan'),
        'gap_max': max(gaps) if gaps else float('nan'),
        'thermal': ' '.join(f'{THERMAL.get(state, "?" )}x{thermal.count(state)}' for state in sorted(set(thermal))),
    }


def format_table(results):
    head = ('variant', 'windows', 'fps mean', 'fps min', 'at 60', 'gpu ms', 'gpu load',
            'wait ms', 'gap p95', 'gap max', 'thermal')
    lines = ['| ' + ' | '.join(head) + ' |', '|' + '---|' * len(head)]
    for name, summary in results:
        lines.append('| ' + ' | '.join([
            name,
            str(summary['windows']),
            f"{summary['fps_mean']:.2f}",
            f"{summary['fps_min']:.2f}",
            f"{summary['at_60']*100:.0f}%",
            f"{summary['gpu_ms_mean']:.1f}",
            f"{summary['gpu_load_mean']:.2f}",
            f"{summary['wait_ms_mean']:.2f}",
            f"{summary['gap_p95']:.1f}",
            f"{summary['gap_max']:.1f}",
            summary['thermal'],
        ]) + ' |')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    env = load_env()
    parser.add_argument('--variants', required=True)
    parser.add_argument('--seconds', type=int, default=60)
    parser.add_argument('--settle', type=int, default=20)
    parser.add_argument('--stop-first', action='store_true')
    parser.add_argument('--hot', action='store_true')
    parser.add_argument('--hot-slots', type=int, default=40, help='how many --seconds slices --hot records (default 40)')
    parser.add_argument('--device', default=env.get('DEVICE'))
    parser.add_argument('--bundle', default=env.get('TOLKARA_BUNDLE_ID'))
    args = parser.parse_args()
    if not args.device:
        die('DEVICE is not set in local.env and --device was not given')
    if not args.bundle:
        die('TOLKARA_BUNDLE_ID is not set in local.env and --bundle was not given')
    global DEVICE, BUNDLE
    DEVICE, BUNDLE = args.device, args.bundle

    chosen = []
    for spec in args.variants.split(','):
        spec = spec.strip()
        if not spec:
            continue
        envs = {}
        if ':' in spec:
            name, _, rest = spec.partition(':')
            values = {}
            for pair in rest.split(';'):
                if not pair.strip():
                    continue
                key, _, value = pair.partition('=')
                key, value = key.strip(), value.strip()
                if key.startswith('env.'):
                    envs[key[4:]] = value
                else:
                    values[key] = value or None
        else:
            if spec not in VARIANTS:
                die(f'unknown variant {spec}; known: {", ".join(VARIANTS)}')
            name, values = spec, dict(VARIANTS[spec])
        chosen.append((name, values, envs))

    stamp = datetime.datetime.now().strftime('%Y-%m-%d_%H.%M.%S')
    out = ROOT / 'logs' / 'perf' / stamp
    out.mkdir(parents=True, exist_ok=True)
    say = print

    pid = app_pid(args.device, args.bundle)
    if pid and not args.stop_first:
        die(f'the app is running (pid {pid}). A live session is not ours to take away: '
            'pass --stop-first if this session is yours to end')
    if pid:
        stop_app(args.device, args.bundle, say)

    # One base config, read from the device so the user's own settings are kept.
    base = out / 'Config.base.wtf'
    pull(CONFIG, base, 'appDataContainer', args.bundle, args.device)
    if not base.is_file():
        die('could not read the game configuration from the device')
    base_text = base.read_text()

    # Error and crash baselines: a run that asserts is not a measurement.
    before_errors = set()
    listing = devicectl('device', 'info', 'files', '--device', args.device, '--domain-type',
                        'appDataContainer', '--domain-identifier', args.bundle, '--username', 'mobile',
                        '--subdirectory', ERRORS, '--json-output', '-')
    try:
        import json
        before_errors = {item['relativePath'] for item in json.loads(listing.stdout)['result']['files']}
    except Exception:
        pass

    results, failures = [], []
    for index, (name, values, envs) in enumerate(chosen):
        say(f'\n== {name}: ' + ', '.join(f'{k}={v}' for k, v in values.items())
            + ('; env ' + ', '.join(f'{k}={v}' for k, v in envs.items()) if envs else ''))
        config = out / f'Config.{name}.wtf'
        config.write_text(set_cvars(base_text, values))
        push(config, CONFIG, args.bundle, args.device)

        launch_args = ['device', 'process', 'launch', '--device', args.device]
        if envs:
            import json
            launch_args += ['-e', json.dumps(envs)]
        launch = devicectl(*launch_args, args.bundle, '--local-game-startup', '--measure-native')
        if launch.returncode:
            failures.append(f'{name}: launch failed: {launch.stderr.strip() or launch.stdout.strip()}')
            continue

        # Wait for the first window (memory preparation is 60-90 s), then settle.
        first = None
        deadline = time.time() + 300
        while time.time() < deadline:
            time.sleep(10)
            log = out / f'{name}.log'
            pull_log(log)
            if windows(log):
                first = log
                break
        if first is None:
            failures.append(f'{name}: no frame-timing window within 300 s (did the guest start?)')
            stop_app(args.device, args.bundle, say)
            continue
        say(f'  first window after {int(300 - (deadline - time.time()))}s; settling {args.settle}s')
        time.sleep(args.settle)

        if args.hot:
            # One long session: sample repeatedly instead of restarting.
            for slice_index in range(1, args.hot_slots + 1):
                time.sleep(args.seconds)
                pull_log(out / f'{name}.log')
                rows = windows(out / f'{name}.log')
                summary = summarise(rows[-max(1, args.seconds // 5):])
                say(f'  [{slice_index * args.seconds:5d}s] fps={summary["fps_mean"]:.2f} '
                    f'gpu={summary["gpu_ms_mean"]:.1f}ms load={summary["gpu_load_mean"]:.2f} '
                    f'wait={summary["wait_ms_mean"]:.2f}ms thermal={summary["thermal"]}')
            pull_log(out / f'{name}.log')
            summary = summarise(windows(out / f'{name}.log'))
            results.append((name, summary))
            break

        time.sleep(args.seconds)
        log = out / f'{name}.log'
        pull_log(log)
        rows = windows(log)
        summary = summarise(rows[-max(1, args.seconds // 5):])
        if summary:
            results.append((name, summary))
        else:
            failures.append(f'{name}: no windows parsed from {log.name}')
        stop_app(args.device, args.bundle, say)

    table = format_table(results) if results else '(no windows)'
    (out / 'summary.md').write_text(f'# Frame pacing sweep {stamp}\n\n{table}\n')
    with (out / 'windows.csv').open('w') as handle:
        names = ['variant', 'seconds', 'fps', 'gap_avg_ms', 'max_gap_ms', 'gpu_ms', 'gpu_load',
                 'wait_ms', 'cpu_submit_avg_ms', 'cpu_submit_max_ms', 'thermal']
        handle.write(','.join(names) + '\n')
        for name, _, _ in chosen:
            for row in windows(out / f'{name}.log'):
                handle.write(','.join([name] + [str(row.get(key, '')) for key in names[1:]]) + '\n')

    say('\n' + table)
    say(f'\nwork files: {out}')
    after = devicectl('device', 'info', 'files', '--device', args.device, '--domain-type',
                      'appDataContainer', '--domain-identifier', args.bundle, '--username', 'mobile',
                      '--subdirectory', ERRORS, '--json-output', '-')
    try:
        import json
        after_errors = {item['relativePath'] for item in json.loads(after.stdout)['result']['files']}
        new_errors = sorted(after_errors - before_errors)
    except Exception:
        new_errors = []
    if new_errors:
        failures.append('new assertion file(s): ' + ', '.join(new_errors))
    if failures:
        say('\nFAILURES:')
        for failure in failures:
            say('  ' + failure)
        sys.exit(1)


if __name__ == '__main__':
    main()
