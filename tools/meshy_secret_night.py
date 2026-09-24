"""Resumable Goa props, using the project's Meshy client and credential handling."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import shutil
from meshy_raven_melee import authenticate, generate, ROOT

SPECS = {
    'goa_stage': (
        'Outdoor forest psytrance DJ stage, standalone complete modular stage prop. Wide raised timber platform, two tall black stacked PA speaker towers flanking a central detailed DJ mixing desk, overhead aluminium truss arch with six moving head fixtures, stretched triangular fabric canopy, large ornate circular mandala backdrop. Open front, no people, no terrain. Professional realistic festival construction, intricate speakers and cables.',
        'Weathered dark timber, black speaker grilles, brushed silver truss, ultraviolet purple cyan and magenta psychedelic mandala fabric, metallic DJ controls, realistic PBR materials without baked lighting.', 26000),
    'goa_totem': (
        'Single freestanding psychedelic forest festival sound totem, carved wooden pillar on stable broad base, crowned with a large ornamental mushroom cap, circular central bronze resonator and intricate spiral carved details, hanging small bells. Full object, no ground, no people.',
        'Dark carved wood, antique bronze resonator, vivid turquoise and violet mushroom cap with intricate pink spiral ornament, realistic physical materials, no baked lights.', 12000),
    'goa_bar': (
        'Standalone rustic outdoor festival bar counter, rough wood counter with many green and amber beer bottles, a ceramic water dispenser with tap, metal cups, little basket of ornamental mushrooms. Two upright wooden posts supporting a narrow fabric awning. Open front, no people, no ground, realistic game environment prop.',
        'Rain darkened wood grain, translucent amber beer bottles and green glass, teal ceramic water dispenser, pink purple patterned awning, realistic roughness and metal cups, no readable text.', 18000),
}

def build(name, spec):
    generate(name, spec)
    destination = ROOT / 'godot/assets/models' / (name + '.glb')
    shutil.copy2(ROOT / 'meshy_output/raven_melee' / name / 'refine.glb', destination)
    print('INSTALLED', destination.name, flush=True)

if __name__ == '__main__':
    authenticate()
    with ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(lambda entry: build(*entry), SPECS.items()):
            pass
