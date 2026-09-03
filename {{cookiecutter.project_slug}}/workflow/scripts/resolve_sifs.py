"""Print the .sif path of every image in the merged config, one per line.

    python workflow/scripts/resolve_sifs.py <config>...
    python workflow/scripts/resolve_sifs.py --images hello,mytool <config>...

Config layers merge in argument order, like multiple --configfile arguments.
--images takes the KEYS under containers.images and errors on an unknown one.
Mirrors common.smk:get_apptainer_path -- keep the two in sync.
"""

import argparse

import yaml

BASE = "workflow/config/config.yaml"


def merge(a, b):
    for k, v in b.items():
        a[k] = merge(a[k], v) if isinstance(v, dict) and isinstance(a.get(k), dict) else v
    return a


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("configs", nargs="*", help="config layers, merged in order")
    ap.add_argument("--images", default="", help="comma-separated image keys to include")
    args = ap.parse_args()

    cfg = yaml.safe_load(open(BASE)) or {}
    for path in args.configs:
        if path != BASE:
            cfg = merge(cfg, yaml.safe_load(open(path)) or {})

    containers = cfg["containers"]
    images = containers["images"]
    keys = [k for k in args.images.split(",") if k] or list(images)
    unknown = [k for k in keys if k not in images]
    if unknown:
        raise SystemExit(
            f"unknown image key(s) {unknown}; configured: {sorted(images)}"
        )
    for key in keys:
        img = images[key]
        print(f'{containers["dir"]}/{img["name"]}_{img["tag"]}.sif')


if __name__ == "__main__":
    main()
