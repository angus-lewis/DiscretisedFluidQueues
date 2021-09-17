abstract type Generator <: AbstractArray{Real,2} end 

const BoundaryFluxTupleType = NamedTuple{(:upper,:lower),Tuple{NamedTuple{(:in,:out),Tuple{Vector{Float64},Vector{Float64}}},NamedTuple{(:in,:out),Tuple{Vector{Float64},Vector{Float64}}}}}

struct LazyGenerator  <: Generator
    model::FluidQueue
    mesh::Mesh
    blocks::Tuple{Array{Float64,2},Array{Float64,2},Array{Float64,2},Array{Float64,2}}
    boundary_flux::BoundaryFluxTupleType
    D::Union{Array{Float64,2},LinearAlgebra.Diagonal{Bool,Array{Bool,1}}}
    function LazyGenerator(
        model::FluidQueue,
        mesh::Mesh,
        blocks::Tuple{Array{Float64,2},Array{Float64,2},Array{Float64,2},Array{Float64,2}},
        boundary_flux::NamedTuple{(:upper,:lower),Tuple{NamedTuple{(:in,:out),Tuple{Vector{Float64},Vector{Float64}}},NamedTuple{(:in,:out),Tuple{Vector{Float64},Vector{Float64}}}}},
        D::Union{Array{Float64,2},LinearAlgebra.Diagonal{Bool,Array{Bool,1}}},
    )
        s = size(blocks[1])
        for b in 1:4
            checksquare(blocks[b]) 
            !(s == size(blocks[b])) && throw(DomainError("blocks must be the same size"))
        end
        checksquare(D)
        !(s == size(D)) && throw(DomainError("blocks must be the same size as D"))
        
        return new(model,mesh,blocks,boundary_flux,D)
    end
end
function LazyGenerator(
    model::Model,
    mesh::Mesh,
    blocks::Tuple{Array{Float64,2},Array{Float64,2},Array{Float64,2}},
    boundary_flux::NamedTuple{(:in, :out),Tuple{Array{Float64,1},Array{Float64,1}}},
    D::Union{Array{Float64,2},LinearAlgebra.Diagonal{Bool,Array{Bool,1}}},
)
    blocks = (blocks[1],blocks[2],blocks[2],blocks[3])
    boundary_flux = (upper = boundary_flux, lower = boundary_flux)
    return LazyGenerator(model,mesh,blocks,boundary_flux,D)
end
function LazyGenerator(
    blocks::Tuple{Array{Float64,2},Array{Float64,2},Array{Float64,2}},
    boundary_flux::NamedTuple{(:in, :out),Tuple{Array{Float64,1},Array{Float64,1}}},
    D::Union{Array{Float64,2},LinearAlgebra.Diagonal{Bool,Array{Bool,1}}},
)
    blocks = (blocks[1],blocks[2],blocks[2],blocks[3])
    boundary_flux = (upper = boundary_flux, lower = boundary_flux)
    return LazyGenerator(blocks, boundary_flux, D)
end
function MakeLazyGenerator(model::Model, mesh::Mesh; v::Bool=false)
    throw(DomainError("Can construct LazyGenerator for DGMesh, FRAPMesh, only"))
end

function size(B::LazyGenerator)
    sz = n_phases(B.model)*total_n_bases(B.mesh) + N₋(B.model.S) + N₊(B.model.S)
    return (sz,sz)
end
size(B::LazyGenerator, n::Int) = size(B)[n]

_check_phase_index(i::Int,model::Model) = (i∉phases(model)) && throw(DomainError("i is not a valid phase in model"))
_check_mesh_index(k::Int,mesh::Mesh) = !(1<=k<=n_intervals(mesh)) && throw(DomainError("k in not a valid cell"))
_check_basis_index(p::Int,mesh::Mesh) = !(1<=p<=n_bases(mesh))

function _map_to_index_interior(i::Int,k::Int,p::Int,model::Model,mesh::Mesh)
    # i phase
    # k cell
    # p basis
    
    _check_phase_index(i,model)
    _check_mesh_index(k,mesh)
    _check_basis_index(p,mesh)

    P = n_bases(mesh)
    KP = total_n_bases(mesh)

    idx = (i-1)*KP + (k-1)*P + p
    return N₋(mesh) + idx 
end
function _map_to_index_boundary(i::Int,model::Model,mesh::Mesh)
    # i phase
    _check_phase_index(i,model)
    if _has_left_boundary(model.S,i) 
        idx = N₋(model.S[1:i])
    else _has_right_boundary(model.S,i)
        N = n_phases(model)
        KP = total_n_bases(mesh)
        idx = N₊(model.S[1:i]) + KP*N + N₋(model.S)
    end
    return idx
end

_is_boundary_index(n::Int,B::LazyGenerator) = (n∈1:N₋(B.model.S))||(n∈(size(B,1).-(0:N₊(B.model.S)-1)))
function _map_from_index_interior(n::Int,B::LazyGenerator)
    # n matrix index to map to phase, cell, basis
    (!(1<=n<=size(B,1))||_is_boundary_index(n,B))&&throw(DomainError(n,"not a valid interior index"))
    
    n -= (N₋(B.model.S)+1)
    N = n_phases(B.model)
    KP = total_n_bases(B.mesh)
    P = n_bases(B.mesh)

    i = (n÷KP) + 1
    k = mod(n,KP)÷P + 1 #(n-1 - (i-1)*KP)÷P + 1
    p = mod(n,P) + 1
    return i, k, p
end
function _map_from_index_boundary(n::Int,B::LazyGenerator)
    # n matrix index to map to phase at boundary
    (!_is_boundary_index(n,B))&&throw(DomainError("not a valid boundary index"))
    
    if n>N₋(B.model.S)
        i₊ = n-N₋(B.model.S)-total_n_bases(B.mesh)*n_phases(B.model)
        i = 1
        for j in phases(B.model.S)
            (i₊==N₊(B.model.S[1:j])) && break
            i += 1
        end
    else 
        i₋ = n
        i = 1
        for j in phases(B.model.S)
            (i₋==N₋(B.model.S[1:j])) && break
            i += 1
        end
    end

    return i
end

function *(u::AbstractArray{Float64,2}, B::LazyGenerator)
    output_type = typeof(u)
    
    sz_u_1 = size(u,1)
    sz_u_2 = size(u,2)
    sz_B_1 = size(B,1)
    sz_B_2 = size(B,2)
    !(sz_u_2 == sz_B_1) && throw(DomainError("Dimension mismatch, u*B, length(u) must be size(B,1)"))

    if output_type <: SparseArrays.SparseMatrixCSC
        v = SparseArrays.spzeros(sz_u_1,sz_B_2)
    else 
        v = zeros(sz_u_1,sz_B_2)
    end
    
    model = B.model
    mesh = B.mesh

    Kp = total_n_bases(mesh) # K = n_intervals(mesh), p = n_bases(mesh)
    C = rates(model)
    n₋ = N₋(model.S)
    n₊ = N₊(model.S)

    # boundaries
    # at lower
    v[:,1:n₋] += u[:,1:n₋]*model.T[_has_left_boundary.(model.S),_has_left_boundary.(model.S)]
    # in to lower 
    idxdown = n₋ .+ ((1:n_bases(mesh)).+Kp*(findall(_has_left_boundary.(model.S)) .- 1)')[:]
    v[:,1:n₋] += u[:,idxdown]*LinearAlgebra.kron(
        LinearAlgebra.diagm(0 => abs.(C[_has_left_boundary.(model.S)])),
        B.boundary_flux.lower.in/Δ(mesh,1),
    )
    # out of lower 
    idxup = n₋ .+ (Kp*(findall(C .> 0).-1)' .+ (1:n_bases(mesh)))[:]
    v[:,idxup] += u[:,1:n₋]*kron(model.T[_has_left_boundary.(model.S),C.>0],B.boundary_flux.lower.out')

    # at upper
    v[:,end-n₊+1:end] += u[:,end-n₊+1:end]*model.T[_has_right_boundary.(model.S),_has_right_boundary.(model.S)]
    # in to upper
    idxup = n₋ .+ ((1:n_bases(mesh)) .+ Kp*(findall(_has_right_boundary.(model.S)) .- 1)')[:] .+
        (Kp - n_bases(mesh))
    v[:,end-n₊+1:end] += u[:,idxup]*LinearAlgebra.kron(
        LinearAlgebra.diagm(0 => C[_has_right_boundary.(model.S)]),
        B.boundary_flux.upper.in/Δ(mesh,n_intervals(mesh)),
    )
    # out of upper 
    idxdown = n₋ .+ (Kp*(findall(C .< 0).-1)' .+ (1:n_bases(mesh)))[:] .+
        (Kp - n_bases(mesh))
    v[:,idxdown] += u[:,end-n₊+1:end]*kron(model.T[_has_right_boundary.(model.S),C.<0],B.boundary_flux.upper.out')

    # innards
    for i in phases(model), j in phases(model)
        if i == j 
            # mult on diagonal
            for k in 1:n_intervals(mesh)
                k_idx = (i-1)*Kp .+ (k-1)*n_bases(mesh) .+ (1:n_bases(mesh)) .+ n₋
                for ℓ in 1:n_intervals(mesh)
                    if (k == ℓ+1) && (C[i] > 0)
                        ℓ_idx = k_idx .- n_bases(mesh) 
                        v[:,k_idx] += C[i]*(u[:,ℓ_idx]*B.blocks[4])/Δ(mesh,ℓ)
                    elseif k == ℓ
                        v[:,k_idx] += (u[:,k_idx]*(abs(C[i])*B.blocks[2 + (C[i].<0)]/Δ(mesh,ℓ) + model.T[i,j]*LinearAlgebra.I))
                    elseif (k == ℓ-1) && (C[i] < 0)
                        ℓ_idx = k_idx .+ n_bases(mesh) 
                        v[:,k_idx] += abs(C[i])*(u[:,ℓ_idx]*B.blocks[1])/Δ(mesh,ℓ)
                    end
                end
            end
        elseif membership(model.S,i)!=membership(model.S,j)# B.pmidx[i,j]
            # changes from S₊ to S₋ etc.
            for k in 1:n_intervals(mesh)
                for ℓ in 1:n_intervals(mesh)
                    if k == ℓ
                        i_idx = (i-1)*Kp .+ (k-1)*n_bases(mesh) .+ (1:n_bases(mesh)) .+ n₋
                        j_idx = (j-1)*Kp .+ (k-1)*n_bases(mesh) .+ (1:n_bases(mesh)) .+ n₋
                        v[:,j_idx] += (u[:,i_idx]*(model.T[i,j]*B.D))
                    end
                end
            end
        else
            i_idx = (i-1)*Kp .+ (1:Kp) .+ n₋
            j_idx = (j-1)*Kp .+ (1:Kp) .+ n₋
            v[:,j_idx] += (u[:,i_idx]*model.T[i,j])
        end
    end
    return v
end

function *(B::LazyGenerator, u::AbstractArray{Float64,2})
    output_type = typeof(u)

    sz_u_1 = size(u,1)
    sz_B_2 = size(B,2)

    !(sz_u_1 == sz_B_2) && throw(DomainError("Dimension mismatch, u*B, length(u) must be size(B,2)"))

    if output_type <: SparseArrays.SparseMatrixCSC
        v = SparseArrays.spzeros(sz_u_1,sz_B_2)
    else 
        v = zeros(sz_u_1,sz_B_2)
    end

    model = B.model
    mesh = B.mesh
    Kp = total_n_bases(mesh) # K = n_intervals, p = n_bases

    C = rates(model)
    n₋ = N₋(model.S)
    n₊ = N₊(model.S)
    # boundaries
    # at lower
    v[1:n₋,:] += model.T[_has_left_boundary.(model.S),_has_left_boundary.(model.S)]*u[1:n₋,:]
    # in to lower 
    idxdown = n₋ .+ ((1:n_bases(mesh)).+Kp*(findall(_has_left_boundary.(model.S)) .- 1)')[:]
    v[idxdown,:] += LinearAlgebra.kron(
        LinearAlgebra.diagm(0 => abs.(C[_has_left_boundary.(model.S)])),
        B.boundary_flux.lower.in/Δ(mesh,1),
    )*u[1:n₋,:]
    # out of lower 
    idxup = n₋ .+ (Kp*(findall(C .> 0).-1)' .+ (1:n_bases(mesh)))[:]
    v[1:n₋,:] += kron(model.T[_has_left_boundary.(model.S),C.>0],B.boundary_flux.lower.out')*u[idxup,:]

    # at upper
    v[end-n₊+1:end,:] += model.T[_has_right_boundary.(model.S),_has_right_boundary.(model.S)]*u[end-n₊+1:end,:]
    # in to upper
    idxup = n₋ .+ ((1:n_bases(mesh)).+Kp*(findall(_has_right_boundary.(model.S)) .- 1)')[:] .+
        (Kp - n_bases(mesh))
    v[idxup,:] += LinearAlgebra.kron(
        LinearAlgebra.diagm(0 => C[_has_right_boundary.(model.S)]),
        B.boundary_flux.upper.in/Δ(mesh,n_intervals(mesh)),
    )*u[end-n₊+1:end,:]
    # out of upper 
    idxdown = n₋ .+ (Kp*(findall(C .< 0).-1)' .+ (1:n_bases(mesh)))[:] .+
        (Kp - n_bases(mesh))
    v[end-n₊+1:end,:] += kron(model.T[_has_right_boundary.(model.S),C.<0],B.boundary_flux.upper.out')*u[idxdown,:]

    # innards
    for i in phases(model), j in phases(model)
        if i == j 
            # mult on diagonal
            for k in 1:n_intervals(mesh)
                k_idx = (i-1)*Kp .+ (k-1)*n_bases(mesh) .+ (1:n_bases(mesh)) .+ n₋
                for ℓ in 1:n_intervals(mesh)
                    if (k == ℓ+1) && (C[i] > 0) # upper diagonal block
                        ℓ_idx = k_idx .- n_bases(mesh) 
                        v[ℓ_idx,:] += C[i]*(B.blocks[4]*u[k_idx,:])/Δ(mesh,ℓ)
                    elseif k == ℓ # diagonal 
                        v[k_idx,:] += ((abs(C[i])*B.blocks[2 + (C[i].<0)]/Δ(mesh,ℓ) + model.T[i,j]*LinearAlgebra.I)*u[k_idx,:])
                    elseif (k == ℓ-1) && (C[i] < 0) # lower diagonal
                        ℓ_idx = k_idx .+ n_bases(mesh) 
                        v[ℓ_idx,:] += abs(C[i])*(B.blocks[1]*u[k_idx,:])/Δ(mesh,ℓ)
                    end
                end
            end
        elseif membership(model.S,i)!=membership(model.S,j) # B.pmidx[i,j]
            # changes from S₊ to S₋ etc.
            for k in 1:n_intervals(mesh)
                for ℓ in 1:n_intervals(mesh)
                    if k == ℓ
                        i_idx = (i-1)*Kp .+ (k-1)*n_bases(mesh) .+ (1:n_bases(mesh)) .+ n₋
                        j_idx = (j-1)*Kp .+ (k-1)*n_bases(mesh) .+ (1:n_bases(mesh)) .+ n₋
                        v[i_idx,:] += (model.T[i,j]*B.D)*u[j_idx,:]
                    end
                end
            end
        else
            i_idx = (i-1)*Kp .+ (1:Kp) .+ n₋
            j_idx = (j-1)*Kp .+ (1:Kp) .+ n₋
            v[i_idx,:] += model.T[i,j]*u[j_idx,:]
        end
    end
    return v
end

*(B::LazyGenerator, u::LazyGenerator) = SparseArrays.SparseMatrixCSC{Float64,Int}(B)*u

function show(io::IO, mime::MIME"text/plain", B::LazyGenerator)
    if VERSION >= v"1.6"
        show(io, mime, SparseArrays.SparseMatrixCSC(Matrix{Float64}(LinearAlgebra.I(size(B,1)))*B))
    else
        show(io, mime, Matrix{Float64}(LinearAlgebra.I(size(B,1)))*B)
    end
end
# show(B::LazyGenerator) = show(stdout, B)

function getindex_interior(B::LazyGenerator,row::Int,col::Int)
    i, k, p = _map_from_index_interior(row,B)
    j, l, q = _map_from_index_interior(col,B)
    
    model = B.model
    mesh = B.mesh
    C = rates(model)

    v=0.0
    if i==j
        if k==l
            v=abs(C[i])*B.blocks[2 + (C[i].<0)][p,q]/Δ(mesh,k) + model.T[i,j]*(p==q)
        elseif k+1==l# upper diagonal blocks
            (C[i]>0) && (v=C[i]*B.blocks[4][p,q]/Δ(mesh,k))
        elseif k-1==l
            (C[i]<0) && (v=abs(C[i])*B.blocks[1][p,q]/Δ(mesh,k))
        end
    elseif membership(model.S,i)!=membership(model.S,j)
        (k==l) && (v=model.T[i,j]*B.D[p,q])
    else
        ((p==q)&&(k==l)) && (v=model.T[i,j])
    end
    return v
end
function getindex_out_boundary(B::LazyGenerator,row::Int,col::Int)
    (!_is_boundary_index(row,B))&&throw(DomainError(row,"row index does not correspond to a boundary"))
    j, l, q = _map_from_index_interior(col,B)
    
    model = B.model
    mesh = B.mesh
    C = rates(model)

    i = _map_from_index_boundary(row,B)
    if (l==1)&&(C[j]>0)&&_has_left_boundary(model.S,i)
        v = model.T[i,j]*B.boundary_flux.lower.out[q]
    elseif (l==n_intervals(mesh))&&(C[j]<0)&&_has_right_boundary(model.S,i)
        v = model.T[i,j]*B.boundary_flux.upper.out[q]
    else 
        v = 0.0
    end
    
    return v
end
function getindex_in_boundary(B::LazyGenerator,row::Int,col::Int)
    (!_is_boundary_index(col,B))&&throw(DomainError(col,"col index does not correspond to a boundary"))
    i, k, p = _map_from_index_interior(row,B)
    
    model = B.model
    mesh = B.mesh
    C = rates(model)
    
    j = _map_from_index_boundary(col,B)
    if (k==1)&&(C[i]<0)&&(i==j)
        v = abs(C[i])*B.boundary_flux.lower.in[p]/Δ(mesh,1)
    elseif (k==n_intervals(mesh))&&(C[i]>0)&&(i==j)
        v = abs(C[i])*B.boundary_flux.upper.in[p]/Δ(mesh,n_intervals(mesh))
    else 
        v = 0.0
    end
    
    return v
end

function getindex(B::LazyGenerator,row::Int,col::Int)
    checkbounds(B,row,col)

    model = B.model

    if _is_boundary_index(row,B) && _is_boundary_index(col,B)
        i = _map_from_index_boundary(row,B)
        j = _map_from_index_boundary(col,B)
        (_has_left_boundary(model.S,i)==_has_left_boundary(model.S,j)) ? (v = model.T[i,j]) : (v=0.0)
    elseif _is_boundary_index(col,B)
        v = getindex_in_boundary(B,row,col)
    elseif _is_boundary_index(row,B)
        v = getindex_out_boundary(B,row,col)
    else
        v = getindex_interior(B,row,col)
    end
    return v
end

export getindex, *

