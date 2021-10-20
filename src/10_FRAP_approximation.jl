"""
    FRAPMesh{T} <: Mesh{T}

A QBD-RAP (FRAM) discretisation scheme for a DiscretisedFluidQueue. 

# Arguments
- `nodes`: the cell edges
- `me`: the MatrixExponential used to approximate model the fluid queue on each cell.
"""
struct FRAPMesh{T} <: Mesh{T}
    nodes::T
    me::AbstractMatrixExponential
end 
FRAPMesh(nodes::AbstractVector{Float64},n_bases::Int) = FRAPMesh(nodes,build_me(cme_params[n_bases]))
function FRAPMesh()
    FRAPMesh(Array{Float64,1}(undef,0),0)
end

"""

    n_bases_per_cell(mesh::FRAPMesh)
    
Number of bases in a cell
"""
n_bases_per_cell(mesh::FRAPMesh) = _order(mesh.me)


"""

    cell_nodes(mesh::FRAPMesh)

The cell centre
"""
cell_nodes(mesh::FRAPMesh) = Array(((mesh.nodes[1:end-1] + mesh.nodes[2:end]) / 2 )')

"""

    basis(mesh::FRAPMesh)

Constant ""
"""
basis(mesh::FRAPMesh) = ""

function build_lazy_generator(
    dq::DiscretisedFluidQueue{FRAPMesh{T}};
    v::Bool=false,
) where T
    me = dq.mesh.me
    blocks = (me.s*me.a, me.S, me.s*me.a)
    boundary_flux = OneBoundaryFlux(me.s[:],me.a[:])
    D = me.D
    out = LazyGenerator(dq,blocks,boundary_flux,D)
    v && println("UPDATE: LazyGenerator object created with keys ", keys(out))
    return out
end
