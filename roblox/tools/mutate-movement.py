"""Independent faults against direct phase-four properties, restoring even on failure.

Run from roblox/: python3 tools/mutate-movement.py
Every fault must reach its expected assertion, not merely crash or fail to compile.
Do not run concurrently with checks, renders, or other edits to the client modules.
"""
from pathlib import Path
import subprocess

# name, module, original, fault, expected assertion
movement = [
    ('crossed shins', 'Posture', 'forward * math.abs(foot.lane)', 'forward', 'gait shins cross'),
    ('crossed thighs', 'Posture', 'if foot and foot.lane then rx = dx end', 'if foot and foot.lane then rx = -dx end', 'gait thighs cross'),
    ('sliding support', 'Movement', 's.x * s.facing * math.pi', '0 * s.facing * math.pi', 'support foot slides'),
    ('feet below floor', 'Movement', '* lift - ch.bob', '* lift - ch.bob - 0.1', 'foot penetrates ground'),
    ('no passing clearance', 'Movement', '* lift - ch.bob', '* 0 - ch.bob', 'support foot slides'),
    ('walk identical to run', 'Movement', 'local run = smooth((speed - 0.42) / 0.28)', 'local run = 0', 'same swing lift'),
    ('arm follows leg', 'Movement', 'm.back = -m.feet[1].x', 'm.back = m.feet[1].x', 'free arm does not oppose'),
    ('torso on another clock', 'Posture', 'motion.phase or s.frameCount * 0.38', 's.frameCount * 0.38', 'hips use a different stride clock'),
    ('frozen torso', 'Posture', 'motion.phase or s.frameCount * 0.38', '0', 'hips never exchange weight'),
    ('load lifts planted feet', 'Movement', 'plant(0.65, 12 + 50 * load)', 'feet(-r, 0.1, 12, r, 0.1, 12)', 'jumpsquat planted foot leaves floor'),
    ('landing feet follow squash', 'Movement', 'plant(0.65, 10 + 65 * load)', 'feet(-r, ch.bob, 10, r, ch.bob, 10)', 'landing planted foot leaves floor'),
    ('landing feet drift', 'Movement', 'plant(0.65, 10 + 65 * load)', 'plant(0.65 + sf * 0.1, 10 + 65 * load)', 'landing planted foot shifts sideways'),
    ('rise without trail', 'Movement', '0.10 + 0.08 * rise', '0.02 + 0.01 * rise', 'rise has no trailing leg'),
    ('flat apex', 'Movement', '0.12 * hang', '0.0 * hang', 'apex never gathers'),
    ('fall never reaches', 'Movement', '0.025 * rise + 0.12 * hang', '0.025 * rise + 0.12', 'rise has no trailing leg'),
    ('fast fall ignored', 'Movement', 'if s.fastFalling then', 'if false then', 'fast fall does not commit'),
    ('shield arm dropped', 'Movement', '1.25 * brace', '0 * brace', 'shield has no brace'),
    ('dodge stays tall', 'Movement', '-h * 0.045 * duck', '0 * duck', 'spot dodge does not duck'),
    ('impact ignores facing', 'Movement', 'else 1) * s.facing', 'else 1) * 1', 'impact ignores launch direction or facing'),
    ('untucked roll', 'Movement', 'h * 0.20 * tuck', '0 * tuck', 'rolling body fails to tuck'),
    ('splayed roll arm', 'Movement', '0.30 - 0.10 * tuck', '0.40', 'rolling support arm stays splayed'),
    ('never gets up', 'Movement', 'ch.rigRotZ * (1 - getup)', 'ch.rigRotZ', 'knockdown never gets up'),
    ('getup foot sinks', 'Movement', '-math.sin(angle) * x - math.cos(angle) * m.yOff - ch.bob', '-math.sin(angle) * x - math.cos(angle) * m.yOff - ch.bob + 0.1', 'getup foot goes through floor'),
    ('getup foot slides', 'Movement', 'math.cos(angle) * x - math.sin(angle) * m.yOff', 'math.cos(angle) * x - math.sin(angle) * m.yOff + 0.1', 'getup foot goes through floor'),
    ('ledge knee dropped', 'Movement', 'r * 0.65, h * 0.17, 76', 'r * 0.65, 0, 10', 'ledge loses overhead reach or climbing knee'),
    ('climb never plants', 'Movement', 'h * 0.22 * (1 - climb)', 'h * 0.22', 'ledge getup never plants'),
    ('climb knee lowers early', 'Movement', 'smooth((sf - 3) / (onStage - 3))', 'smooth(sf / onStage)', 'ledge getup never plants'),
    ('late platform contact', 'Movement', 'then 8 else 10', 'then 14 else 16', 'ledge action feet miss platform arrival'),
    ('overwritten attack', 'Movement', 'state == "run" and s.onGround', '(state == "run" and s.onGround) or state == "attack"', 'movement overwrote authored action'),
    ('snapshot written', 'Movement', 'local m: any =', 's.vx = 0\n\tlocal m: any =', 'readonly table'),
    ('channels written', 'Movement', 'local m: any =', 'ch.bob = 0\n\tlocal m: any =', 'readonly table'),
]
secondary = [
    ('missing rear hair', 'Secondary', 'layer.z == 10', 'layer.z == 999', 'catalogue tail missing or priority wrong'),
    ('wrong accessory priority', 'Secondary', 'if neck == "summitMantle" or neck == "scarf" then', 'if false then', 'catalogue tail missing or priority wrong'),
    ('rigid part trails', 'Secondary', 'layer.z == 10 and layer.y >= 8', 'layer.z == 50', 'rigid kit part grows a trailing sprite'),
    ('uncached art', 'Secondary', 'if cache[code] then return cache[code] end', 'if false then return cache[code] end', 'secondary art rebuilt per call'),
    ('oversize picture', 'Secondary', 'maxX - minX + 3', 'maxX - minX + 300', 'small-sprite budget'),
    ('duplicate painted tail', 'Secondary', 'glyph = "."', 'glyph = glyph', 'cut leaves a duplicate painted tail'),
    ('uncached cut expression', 'Secondary', 'if not art.heads[expression] then', 'if true then', 'expression cut rebuilt'),
    ('neutral cut expression', 'Secondary', 'Expressions.specFor(art.spec, expression)', 'Expressions.specFor(art.spec, "neutral")', 'cut expression is visually neutral'),
    ('expression restores hair', 'Secondary', 'cuts[art.category] = art.override[art.category]', 'cuts[art.category] = nil', 'expression repaints detached rear hair'),
    ('hat trim ignored', 'Secondary', 'and y >= trim', 'and y >= 0', 'tail restores hair clipped by headwear'),
    ('no lag', 'Secondary', 'old.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5))', 'old.angle = target', 'tail has no delayed trail'),
    ('never settles', 'Secondary', 'old.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5))', 'if s.state == "run" then old.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5)) end', 'tail snaps still when movement stops'),
    ('duplicate draw advances follower', 'Secondary', 'elseif fc > old.at then\n\t\told.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5))', 'elseif fc >= old.at then\n\t\told.angle += (target - old.angle) * (1 - math.exp(-math.max(1, fc - old.at) / 5))', 'duplicate draw advances lag'),
    ('seek keeps old motion', 'Secondary', 'or fc < old.at', 'or false', 'seek retains old secondary state'),
    ('facing ignored', 'Secondary', 's.vx * s.facing / char.runSpeed', 's.vx / char.runSpeed', 'tail leads motion when facing left'),
    ('detached root', 'Secondary', 'x += dx * sx * cs - dy * sy * sn', 'x += dx * sx * cs - dy * sy * sn + 0.1', 'trailing root detached x'),
    ('sheared tail', 'Fighter2D', 'Canvas2D.rotate(c, trail.rot)\n\t\t\tCanvas2D.scale(c, trail.sx, trail.sy)', 'Canvas2D.scale(c, trail.sx, trail.sy)\n\t\t\tCanvas2D.rotate(c, trail.rot)', 'secondary draw shears a sprite'),
    ('tail drawn twice', 'Fighter2D', 'trail.pw, trail.ph, trailingArt.w, trailingArt.h)', 'trail.pw, trail.ph, trailingArt.w, trailingArt.h)\n\t\t\tCanvas2D.sprite(c, `secondary|{kitCode}`, trailingArt.full, -2 * trail.pw, trail.ph, trail.pw, trail.ph, trailingArt.w, trailingArt.h)', 'expected exactly one tail'),
    ('extra tail at match LOD', 'Fighter2D', 'if kitArt and not half then Secondary.art', 'if kitArt then Secondary.art', 'expected exactly one tail'),
    ('per-frame picture change', 'Fighter2D', '`secondary|{kitCode}`, trailingArt.full', '`secondary|{kitCode}`, table.clone(trailingArt.full)', 'movement changes the trailing picture'),
    ('time-dependent sprite keys', 'Fighter2D', '`secondary|{kitCode}`', '`secondary|{kitCode}|{s.frameCount}`', 'warm movement rebuilds pictures'),
    ('unbounded art cache', 'Secondary', 'if #order > Secondary.CACHE_MAX then', 'if false then', 'secondary cache is unbounded'),
]

for suite, faults in [('movement', movement), ('secondary', secondary)]:
    subprocess.run(['lune', 'run', f'tests/{suite}'], check=True)
    for name, module, old, new, expected in faults:
        path = Path(f'src/client/{module}.luau')
        source = path.read_bytes()
        text = source.decode()
        assert text.count(old) == 1, (name, text.count(old))
        try:
            path.write_text(text.replace(old, new))
            result = subprocess.run(['lune', 'run', f'tests/{suite}'], capture_output=True, text=True)
            output = result.stdout + result.stderr
            assert result.returncode != 0, f'SURVIVED: {name}'
            assert expected in output, f'WRONG FAILURE: {name}\n{output}'
            line = next(line for line in output.splitlines() if expected in line)
            print(f'CAUGHT {suite}/{name}: {line}', flush=True)
        finally:
            path.write_bytes(source)
    subprocess.run(['lune', 'run', f'tests/{suite}'], check=True)
print(f'All {len(movement) + len(secondary)} independent mutations rejected; sources restored.')
