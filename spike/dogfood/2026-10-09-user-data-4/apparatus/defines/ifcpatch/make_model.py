"""Write a small IFC4 model: a project, a site, a building and five walls, with fixed GlobalIds so
two runs of the seed write the same bytes. ifcopenshell 0.9 creates entities on the file itself.

    python3 make_model.py <path>
"""
import sys
import ifcopenshell

f = ifcopenshell.file(schema="IFC4")
gid = iter(f"{i:022d}".replace("0", "A") for i in range(1, 100))
proj = f.createIfcProject(next(gid), None, "House")
site = f.createIfcSite(next(gid), None, "Site")
bldg = f.createIfcBuilding(next(gid), None, "Building")
f.createIfcRelAggregates(next(gid), None, None, None, proj, [site])
f.createIfcRelAggregates(next(gid), None, None, None, site, [bldg])
walls = [f.createIfcWall(next(gid), None, f"Wall {i}") for i in range(5)]
dup = f.createIfcWall(next(gid), None, "Wall 0")
f.createIfcRelContainedInSpatialStructure(next(gid), None, None, None, walls + [dup], bldg)
f.write(sys.argv[1])
