"""Resume the player's Meshy generation using the project's local credentials."""
import runpy
import shutil
import subprocess
import sys
from progression_assets import authenticate

authenticate()
sys.argv = ['gen_asset.py', 'player_survivor', '--rig', '--pbr',
            '--pose', 't-pose', '--polycount', '22000', '--height', '1.8']
runpy.run_path('tools/gen_asset.py', run_name='__main__')
shutil.copy2('assets/raw/player_survivor/anim_walking.glb',
             'assets/raw/player_survivor/anim_walk.glb')
subprocess.run(['node', 'tools/pack.mjs', 'player_survivor', '--size', '2048'], check=True)
subprocess.run(['node', 'tools/finish_titan.mjs', 'player_survivor'], check=True)
