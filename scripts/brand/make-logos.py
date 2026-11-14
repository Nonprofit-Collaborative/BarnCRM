#!/usr/bin/env python3
"""Builds BarnCRM's packaged logos and the Home welcome image from the Patch brand masters.

    python3 scripts/brand/make-logos.py --source <patch-assets folder> [--out DIR]

Patch, the highland cow, is BarnCRM's mascot (ADR-NEXT, replacing the drawn barn of ADR-0102).
The masters are cut-out transparent PNGs kept outside the repository, in the brand folder's
`patch-assets/` (its `manifest.md` records each file's source and processing). This script only
scales them: each logo is the master's 1024 x 1024 `hires/` file downscaled to 256 x 256 RGBA
with Lanczos filtering on premultiplied alpha, so edges keep no halo. Patch is never redrawn,
recolored or stretched (every master is square, and the welcome pose keeps its aspect ratio).

  Asset (ContentAsset)               Package       Master (hires/)               App
  BarnCRM_Patch_Logo                 core          marks/barncrm-icon            BarnCRM, BarnCRM Standard
  BarnCRM_Patch_Admin_Logo           core          marks/barncrm-circular-badge  BarnCRM Admin, Admin Console
  BarnCRM_Patch_Fundraising_Logo     giving        modules/giving-logo           BarnCRM Fundraising
  BarnCRM_Patch_Volunteers_Logo      volunteers    modules/volunteers-logo       BarnCRM Volunteers
  BarnCRM_Patch_Programs_Logo        programs      modules/programs-logo         BarnCRM Programs
  BarnCRM_Patch_Funders_Logo         funders       modules/funders-logo          BarnCRM Grants
  BarnCRM_Patch_Logic_Models_Logo    logicmodels   modules/logic-models-logo     (Module Manager tile)
  BarnCRM_Patch_Forms_Logo           forms         modules/forms-logo            BarnCRM Forms
  BarnCRM_Patch_Events_Logo          events        modules/event-management-logo BarnCRM Events
  BarnCRM_Patch_Projects_Logo        projects      modules/project-management-logo BarnCRM Projects
  BarnCRM_Patch_Corporate_Hub_Logo   corporatehub  marks/barncrm-icon (for now)  BarnCRM Corporate Hub
  BarnCRM_Patch_Portal_Logo          portal        modules/portal-builder-logo   BarnCRM Portal Builder

Plus Core's static resource `BarnPatchWelcome` (hires/poses/hi-im-patch, 400 px wide), shown by
c/hubWelcome on BarnCRM Home.

A changed image needs a new asset name: redeploying a ContentAsset under its old name keeps the
org's existing image. So the Patch logos have new names, and the old barn assets are removed
from the repository, which puts them in each release's destructive manifest
(scripts/org/build-destructive-manifest.py). Each package ships its own asset, because an app
names a ContentAsset by its API name and a module may not depend on Core's asset once the
packages are namespaced.

Writes `packages/<package>/main/default/contentassets/<Name>.asset` and its `.asset-meta.xml`,
the static resource, and a copy of each logo as `docs/brand/barncrm-<slug>-logo.png`, all under
`--out` (default: the repository root). Needs Pillow. The same masters give the same bytes. The
masters folder's own `contact-sheet.png` shows every mark on light and navy backgrounds.
"""

import argparse
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZE = 256
WELCOME_WIDTH = 400

# (package, asset name, docs/brand slug, master under hires/)
LOGOS = [
    ("core", "BarnCRM_Patch_Logo", "", "marks/barncrm-icon.png"),
    ("core", "BarnCRM_Patch_Admin_Logo", "admin", "marks/barncrm-circular-badge.png"),
    ("giving", "BarnCRM_Patch_Fundraising_Logo", "giving", "modules/giving-logo.png"),
    ("volunteers", "BarnCRM_Patch_Volunteers_Logo", "volunteers", "modules/volunteers-logo.png"),
    ("programs", "BarnCRM_Patch_Programs_Logo", "programs", "modules/programs-logo.png"),
    ("funders", "BarnCRM_Patch_Funders_Logo", "funders", "modules/funders-logo.png"),
    ("logicmodels", "BarnCRM_Patch_Logic_Models_Logo", "logic-models", "modules/logic-models-logo.png"),
    ("forms", "BarnCRM_Patch_Forms_Logo", "forms", "modules/forms-logo.png"),
    ("events", "BarnCRM_Patch_Events_Logo", "events", "modules/event-management-logo.png"),
    ("projects", "BarnCRM_Patch_Projects_Logo", "projects", "modules/project-management-logo.png"),
    # The corporate-hub-logo master's crop takes in part of the source sheet's caption (black
    # "rat" over the tie), so Corporate Hub uses the main mark until the master is cut again;
    # the re-cut image then needs a new asset name.
    ("corporatehub", "BarnCRM_Patch_Corporate_Hub_Logo", "corporate-hub", "marks/barncrm-icon.png"),
    ("portal", "BarnCRM_Patch_Portal_Logo", "portal", "modules/portal-builder-logo.png"),
]
WELCOME = ("core", "BarnPatchWelcome", "poses/hi-im-patch.png")

ASSET_META = """<?xml version="1.0" encoding="UTF-8" ?>
<ContentAsset xmlns="http://soap.sforce.com/2006/04/metadata">
  <isVisibleByExternalUsers>false</isVisibleByExternalUsers>
  <language>en_US</language>
  <masterLabel>{name}</masterLabel>
  <relationships>
    <organization>
      <access>VIEWER</access>
    </organization>
  </relationships>
  <versions>
    <version>
      <number>1</number>
      <pathOnClient>{name}.png</pathOnClient>
    </version>
  </versions>
</ContentAsset>
"""

RESOURCE_META = """<?xml version="1.0" encoding="UTF-8" ?>
<StaticResource xmlns="http://soap.sforce.com/2006/04/metadata">
  <cacheControl>Public</cacheControl>
  <contentType>image/png</contentType>
  <description>
    Patch, the BarnCRM highland cow, waving hello: the welcome image on BarnCRM
    Home (c/hubWelcome). Built by scripts/brand/make-logos.py.
  </description>
</StaticResource>
"""


def scaled(path, width, height):
    """The master at width x height, resampled on premultiplied alpha."""
    with Image.open(path) as image:
        rgba = image.convert("RGBA")
    return rgba.convert("RGBa").resize((width, height), Image.LANCZOS).convert("RGBA")


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "wb" if isinstance(data, bytes) else "w"
    with open(path, mode) as handle:
        handle.write(data)


def save_png(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", required=True, help="the patch-assets folder")
    parser.add_argument("--out", default=ROOT, help="where packages/ and docs/brand/ are written")
    args = parser.parse_args()
    hires = os.path.join(args.source, "hires")

    for package, name, slug, master in LOGOS:
        image = scaled(os.path.join(hires, master), SIZE, SIZE)
        folder = os.path.join(args.out, "packages", package, "main/default/contentassets")
        save_png(image, os.path.join(folder, name + ".asset"))
        write(os.path.join(folder, name + ".asset-meta.xml"), ASSET_META.format(name=name))
        brand = f"barncrm-{slug}-logo.png" if slug else "barncrm-logo.png"
        save_png(image, os.path.join(args.out, "docs/brand", brand))
        print(f"{package}: {name}")

    package, name, master = WELCOME
    with Image.open(os.path.join(hires, master)) as pose:
        height = round(pose.height * WELCOME_WIDTH / pose.width)
    folder = os.path.join(args.out, "packages", package, "main/default/staticresources")
    save_png(scaled(os.path.join(hires, master), WELCOME_WIDTH, height),
             os.path.join(folder, name + ".png"))
    write(os.path.join(folder, name + ".resource-meta.xml"), RESOURCE_META)
    print(f"{package}: {name} ({WELCOME_WIDTH} x {height})")


if __name__ == "__main__":
    main()
