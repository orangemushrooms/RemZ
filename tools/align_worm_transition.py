"""Match the shipped worms' recovery entry to the preceding attack endpoint.

Only existing animation quaternion bytes change; meshes, textures and bind poses remain intact.
Run after regenerating either worm: python tools/align_worm_transition.py --fix
Without --fix this verifies the boundary and exits nonzero when alignment is needed.
"""
import argparse
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def aligned(path):
    data = bytearray(path.read_bytes())
    magic, version, length = struct.unpack_from("<III", data)
    if (magic, version, length) != (0x46546C67, 2, len(data)):
        raise ValueError("Unexpected GLB header: "+str(path))
    json_length, json_kind = struct.unpack_from("<II", data, 12)
    if json_kind != 0x4E4F534A: raise ValueError("GLB JSON chunk missing")
    document = json.loads(data[20:20+json_length])
    binary_length, binary_kind = struct.unpack_from("<II", data, 20+json_length)
    binary_start = 28+json_length
    if binary_kind != 0x004E4942 or binary_start+binary_length > len(data):
        raise ValueError("GLB binary chunk missing")

    def keys(name):
        animation = next(item for item in document["animations"] if item["name"] == name)
        result = {}
        for channel in animation["channels"]:
            if channel["target"]["path"] != "rotation": continue
            sampler = animation["samplers"][channel["sampler"]]
            accessor = document["accessors"][sampler["output"]]
            view = document["bufferViews"][accessor["bufferView"]]
            if accessor["componentType"] != 5126 or accessor["type"] != "VEC4" or "sparse" in accessor or sampler.get("interpolation", "LINEAR") != "LINEAR":
                raise ValueError("Expected dense linear float quaternion tracks")
            index = accessor["count"]-1 if name == "attack" else 0
            offset = binary_start+view.get("byteOffset", 0)+accessor.get("byteOffset", 0)+index*view.get("byteStride", 16)
            if offset < binary_start or offset+16 > binary_start+binary_length:
                raise ValueError("Animation sample outside GLB buffer")
            result[channel["target"]["node"]] = offset
        return result

    attack, recovery = keys("attack"), keys("recovery")
    if set(attack) != set(recovery) or len(attack) != 22:
        raise ValueError("Expected matching 22-bone animation tracks")
    changes = 0
    for bone, source in attack.items():
        destination = recovery[bone]
        if data[source:source+16] != data[destination:destination+16]:
            data[destination:destination+16] = data[source:source+16]
            changes += 1
    return data, changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fix", action="store_true")
    args = parser.parse_args()
    prepared = []
    for name in ("zombie_earthworm", "zombie_earthworm_ancient"):
        path = ROOT/"godot/assets/models"/(name+".glb")
        data, changes = aligned(path)
        prepared.append((path, data, changes))
    for path, data, changes in prepared:
        if args.fix and changes: path.write_bytes(data)
        print(f"{path.stem}: {'aligned' if args.fix else 'check'} changed_tracks={changes}")
    return 0 if args.fix or not any(changes for _, _, changes in prepared) else 1


if __name__ == "__main__": raise SystemExit(main())
