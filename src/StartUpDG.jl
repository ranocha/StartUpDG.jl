module StartUpDG

using ConstructionBase  # for constructorof(...)
using LinearAlgebra     # for diagm, identity matrix I
using StaticArrays      # for SMatrix
using Setfield          # for "modifying" structs to modify node mappings (setproperties)

using Reexport 
@reexport using UnPack            # for getting values in RefElemData and MeshData
@reexport using NodesAndModes     # for basis functions

using NodesAndModes: meshgrid
using SparseArrays: sparse, droptol!

# reference element utility functions
export RefElemData
include("RefElemData.jl")
include("ref_elem_utils.jl")

export MeshData
include("MeshData.jl")

# ref-to-physical geometric terms
export geometric_factors
include("geometric_mappings.jl")

# spatial connectivity routines
export make_periodic
include("connectivity_functions.jl")

# uniform meshes + face vertex orderings are included
export readGmsh2D, uniform_mesh
include("simple_meshes.jl")

# simple explicit time-stepping included for conveniencea
export ck45, dp56, PIparams, compute_adaptive_dt, bcopy! # LSERK 45 + Dormand-Prince 56
include("explicit_timestep_utils.jl")

end