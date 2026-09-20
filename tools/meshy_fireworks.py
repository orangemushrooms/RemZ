"""Generate the two requested firework props with the existing resumable Meshy workflow."""
from concurrent.futures import ThreadPoolExecutor
from meshy_raven_melee import generate, authenticate

SPECS = {
    'firework_rocket': (
        'One realistic premium consumer firework sky rocket, upright pointing up, on a long thin straight natural wooden guide stick. Slim cylindrical cardboard rocket body with a pointed conical paper nose cap, short braided green fuse protruding from the bottom of the cardboard body. Body occupies upper third of overall height, guide stick extends down below. Authentic manufactured paper and wood proportions. Single isolated complete product, unlit, no sparks, no flame, no base, no stand, no background objects, no hands. High quality game prop with modeled seams and paper lip.',
        'Premium deep midnight blue printed paper wrapper with tasteful gold stars and thin gold bands, burgundy red conical paper nose, subtle cardboard grain and folded paper seams. Natural pale wood guide stick, braided green cotton fuse. Photoreal PBR, no readable text, no baked lighting.', 10000),
    'firework_cracker': (
        'One realistic consumer firecracker, single short thick cylindrical red paper tube standing upright, with slightly crimped paper end caps and one short curved braided green fuse protruding from the top. Compact authentic cardboard object, cylinder height three times its diameter. Modeled folded paper edges, raised paper wrap seam. No bundle, no dynamite, no wires, no timer, no stand, no background, no hands, unlit with no smoke or sparks. Photoreal game prop.',
        'Deep vermilion red matte paper wrapper with subtle paper fibers, elegant thin black and antique gold bands, kraft cardboard crimped end caps, tightly braided green cotton fuse. Slight natural creases, premium realistic PBR product, no readable text and no baked lighting.', 8000),
}

if __name__ == '__main__':
    authenticate()
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = [pool.submit(generate, name, spec) for name, spec in SPECS.items()]
        for job in jobs:
            job.result()
