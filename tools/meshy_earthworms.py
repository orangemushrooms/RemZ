"""Resumable Meshy worm models. Original assets/receipts stay in meshy_output.

Meshy's public rigging API does not support limbless creatures. Animation and
skinning are authored by prepare_earthworms.mjs, never billed as Meshy animation.
"""
import sys
from concurrent.futures import ThreadPoolExecutor
from progression_assets import authenticate
from meshy_raven_melee import generate

SPECS = {
    'zombie_earthworm': (
        'Single terrifying colossal undead earthworm, complete elongated limbless body standing straight vertically, tail at bottom and head at top, neutral straight pose for animation rigging. Body length six times its width, thick round cylindrical cross section, dozens of clearly sculpted annular earthworm segments, thick ridged clitellum collar below head, tapered closed tail. Huge circular open mouth at the upper front with concentric hooked ivory teeth, four short fleshy lip lobes, dark deep throat. Necrotic wrinkled skin with torn scars and embedded soil, sparse broken bristles. Anatomical annelid monster, realistic survival horror game creature. No arms, no legs, no eyes, no wings, no ground, no pedestal, no scenery, single connected body.',
        'Photoreal PBR undead earthworm: desaturated purple brown decaying leathery flesh, deep annular grooves with wet dark soil, bruised grey olive patches, dark red cracked mouth tissue, yellow ivory hooked teeth, black wet throat. Restrained moist roughness, detailed pores and scars, realistic normal and roughness maps, no baked lighting.', 26000),
    'zombie_earthworm_ancient': (
        'Single colossal ancient undead earthworm queen, complete long limbless body straight upright vertical, tail bottom head top, neutral straight pose for skeletal animation. Length six times width, thick cylindrical body tapering to tail, heavy annular segments, overlapping rough calcified skin ridges, wide swollen clitellum collar. Upper head has a huge circular toothed maw facing forward and slightly upward, three rings of inward hooked teeth, torn fleshy lip plates, deep dark throat. Jagged short bone growths along segmented back, cracked diseased skin and old wounds. Intimidating realistic rural survival horror creature. No limbs, no eyes, no wings, no humanoid features, no ground or base, single connected body.',
        'Photoreal PBR ancient zombie annelid, charcoal brown and ashen grey dead skin, crusted pale bone plates, dried soil in segment seams, deep wine red bruising, dark wet circular mouth, stained yellow ivory teeth. Detailed wrinkled pores, cracks and weathering, varied roughness, no painted highlights or baked shadows.', 30000),
}
SPECS['zombie_earthworm_ancient_v2'] = (
    'One giant monstrous earthworm. One single head at the TOP end of a very long straight upright cylindrical worm body, pointed closed tail at BOTTOM. Absolutely no arms or legs or hands or feet. Hundreds of ring shaped annular body segments, thick muscular round cross section tapering at tail, large raised clitellum collar near top. Head is a circular open mouth full of concentric sharp hooked teeth, like a lamprey. No eyes or face. Continuous limbless tubular anatomy from mouth to tail. Straight vertical pose for rigging, full body, length six times diameter. Realistic dark horror sculpture of an annelid. Only one mouth and one body, no extra creatures, no branches, no scenery, no ground, no base.',
    'Realistic PBR earthworm skin, ashen grey and dark brown dead leathery flesh, thick calcified annular ridges, wet dirt in segment seams, purple bruising, cracked olive skin, dark wine red mouth tissue, stained ivory hooked teeth. Fine pores, detailed roughness and normal maps, no baked lighting.', 28000)

if __name__ == '__main__':
    authenticate()
    # The shared runner uses the bundled meshy_task helpers for all API operations.
    with ThreadPoolExecutor(max_workers=2) as pool:
        names = sys.argv[1:] or ['zombie_earthworm', 'zombie_earthworm_ancient_v2']
        jobs = [pool.submit(generate, name, SPECS[name]) for name in names]
        for job in jobs:
            job.result()
