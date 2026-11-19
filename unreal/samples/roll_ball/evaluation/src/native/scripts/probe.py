"""Bounded authoring capability probe; produces evidence but never scores."""
import argparse
from runtime import Player, write
from navigation import Navigator
p=argparse.ArgumentParser()
for name in ('pwsh','tools','engine','project','root'):p.add_argument('--'+name,required=True)
p.add_argument('--navigate',action='store_true')
a=p.parse_args();options=vars(a).copy();navigate=options.pop('navigate');player=Player(**options)
try:
    print(player.start(),flush=True)
    player.observe(1); player.capture('initial')
    if navigate:
        nav=Navigator(player);nav.calibrate();print('calibrated',nav.axes,nav.accel,flush=True)
        nav.follow((9,9),stop_status='maze_complete');player.capture('complete');write(player.root/'navigation.json',nav.events)
    else:
        player.keys(['W']);player.observe(.4);player.capture('movement');player.keys([])
        player.observe(.4);player.capture('coast')
    print(player.read(),flush=True)
finally:player.close()
