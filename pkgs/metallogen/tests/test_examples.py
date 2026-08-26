"""Offline tests built from MetalloGen's own examples/ directory.

MetalloGen ships no test suite.  MetalloGen/test.py, the one file whose name
suggests otherwise, is the package's main module -- it defines TMCGenerator and
is what `python -m MetalloGen` ends up in.  What the repository does ship is
examples/, where each `commands` file records a real invocation and the
result_*.xyz files beside it record what that invocation produced.

Those invocations cannot be replayed here.  They drive Gaussian, ORCA or xtb,
and their working directories are absolute paths on someone else's machine
(/home/rxn_grp/scratch/metallogen_test/).  But the *inputs* and the *recorded
outputs* are both in the tree, which is enough to exercise everything in
MetalloGen that does not need a quantum chemistry program: the mSMILES parser,
the SDF reader, and the geometry tables that both consult.

The strongest assertions here are the cross-checks.  An .xyz second line is
"charge multiplicity energy", and the parsers derive charge and multiplicity
independently of the file -- so comparing them catches a parser that silently
changes its mind, which counting atoms alone would not.
"""

import collections
import pathlib

import pytest

from MetalloGen import globalvars as gv
from MetalloGen import om

EXAMPLES = pathlib.Path(__file__).resolve().parents[1] / "examples"

# The two invocations in examples/msmiles_examples/commands, with the -s
# argument lifted out verbatim.
ZR_MSMILES = (
    "[Zr+4]|[Cl-:2]|[Cl-:3]|"
    "[N:1]1=C(C[C-:4]2[CH:4]=[CH:4][CH:4]=[CH:4]2)C=CC=C1(C[C-:5]3[CH:5]=[CH:5][CH:5]=[CH:5]3)|"
    "5_trigonal_bipyramidal"
)
RH_MSMILES = "[Rh+3]|CC[C-:1]=O|[C-:2]#[O+]|[C-:3]#[O+]|[H-:4]|[C-:5]#[O+]|[H-:6]|6_octahedral"


def read_xyz(path):
    """Return (element counts, charge, multiplicity) from an .xyz file.

    MetalloGen writes "charge multiplicity energy" as the comment line rather
    than a comment, which is what makes these files usable as references.
    """
    lines = path.read_text().splitlines()
    count = int(lines[0].split()[0])
    charge, multiplicity = (int(field) for field in lines[1].split()[:2])
    elements = collections.Counter(line.split()[0] for line in lines[2 : 2 + count])
    assert sum(elements.values()) == count, f"{path} declares {count} atoms"
    return elements, charge, multiplicity


def composition(metal_complex):
    return collections.Counter(atom.get_element() for atom in metal_complex.get_atom_list())


def test_msmiles_zirconium_matches_its_recorded_result():
    """examples/msmiles_examples/example_1, parsed and checked against its output."""
    metal_complex = om.get_om_from_modified_smiles(ZR_MSMILES)

    assert metal_complex.center_atom.get_element() == "Zr"
    assert metal_complex.geometry_type.geometry_name == "5_trigonal_bipyramidal"
    assert metal_complex.geometry_type.get_steric_number() == 5
    # Three ligands supplying five binding sites: two chlorides and one
    # tridentate N,Cp,Cp -- which is why the ligand count and the steric number
    # disagree, and worth asserting because a parser that flattened the
    # tridentate into three would still get the atom count right.
    assert len(metal_complex.ligands) == 3
    assert len(metal_complex.get_binding_groups()) == 5

    elements, charge, multiplicity = read_xyz(
        EXAMPLES / "msmiles_examples" / "example_1" / "result_1.xyz"
    )
    assert composition(metal_complex) == elements
    assert metal_complex.num_atom == sum(elements.values())
    assert metal_complex.chg == charge
    assert metal_complex.multiplicity == multiplicity


def test_msmiles_rhodium_parses():
    """examples/msmiles_examples/example_2 -- structure only, deliberately.

    There is no cross-check against result_*.xyz here, because upstream's
    example_2 directory does not contain the results of the command in its own
    `commands` file.  Every result_*.xyz in it, and final_relax_0.com too, is
    the Zr complex from example_1 -- the ORCA input literally opens with
    "Zr 0.0 0.0 0.0".  Asserting against those files would be asserting that
    the Rh parse produces a Zr complex.
    """
    metal_complex = om.get_om_from_modified_smiles(RH_MSMILES)

    assert metal_complex.center_atom.get_element() == "Rh"
    assert metal_complex.geometry_type.geometry_name == "6_octahedral"
    assert metal_complex.geometry_type.get_steric_number() == 6
    # Six monodentate ligands, so here the two counts do agree.
    assert len(metal_complex.ligands) == 6
    assert len(metal_complex.get_binding_groups()) == 6
    assert metal_complex.num_atom == 18
    # Rh, one propanoyl (C3H5O), three carbonyls (C3O3) and two hydrides.
    assert composition(metal_complex) == {"Rh": 1, "C": 6, "O": 4, "H": 7}


@pytest.mark.parametrize(
    ("name", "metal", "geometry", "ligands"),
    [
        ("CIXDAS", "Cu", "4_square_planar", 2),
        ("TIMJUU", "V", "5_trigonal_bipyramidal", 5),
    ],
)
def test_sdf_example_matches_its_recorded_result(name, metal, geometry, ligands):
    """The SDF reader, against both examples/sdf_examples entries.

    Unlike example_2 above, these two directories are self-consistent: the
    recorded result is the complex the .sdf describes.  CIXDAS is the more
    valuable of the two because it is an open-shell doublet, so the derived
    multiplicity is 2 and a parser that hard-coded singlets would fail here and
    nowhere else.
    """
    metal_complex = om.get_om_from_sdf(str(EXAMPLES / "sdf_examples" / name / f"{name}.sdf"))

    assert metal_complex.center_atom.get_element() == metal
    assert metal_complex.geometry_type.geometry_name == geometry
    assert len(metal_complex.ligands) == ligands

    elements, charge, multiplicity = read_xyz(
        EXAMPLES / "sdf_examples" / name / "result_1.xyz"
    )
    assert composition(metal_complex) == elements
    assert metal_complex.num_atom == sum(elements.values())
    assert metal_complex.chg == charge
    assert metal_complex.multiplicity == multiplicity


ALL_GEOMETRIES = sorted(
    (coordination_number, geometry)
    for coordination_number, names in gv.CN_known_geometries_dict.items()
    for geometry in names
)


@pytest.mark.parametrize(("coordination_number", "geometry"), ALL_GEOMETRIES)
def test_geometry_vector_count_matches_coordination_number(coordination_number, geometry):
    """Every geometry filed under coordination number N must supply N directions.

    Geometry.get_steric_number() is just len(direction_vector), and the geometry
    is chosen by looking up the coordination number, so a table where the two
    disagree hands out a steric number that contradicts the lookup that found
    it.

    One entry does disagree, and it is xfail(strict=True) rather than skipped or
    filtered out: if upstream fixes the table, this test starts failing and says
    so, which is the only way anyone here would notice.
    """
    if geometry == "8_bicapped_trigonal_prismatic":
        pytest.xfail("upstream lists 9 direction vectors for a CN-8 geometry")
    assert len(gv.known_geometries_vector_dict[geometry]) == coordination_number
