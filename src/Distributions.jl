# import Base: getindex, size, *

struct SFMDistribution{T<:SFFM.Mesh} <: AbstractArray{Float64,2} 
    coeffs::Array{Float64,2}
    model::SFFM.Model
    mesh::T
    Fil::SFFM.IndexDict
    function SFMDistribution{T}(
        coeffs::Array{Float64,2}, 
        model::SFFM.Model,
        mesh::T,
        Fil::SFFM.IndexDict=SFFM.MakeFil(model,mesh.Nodes),
        ) where T<:SFFM.Mesh
        return (size(coeffs,1)==1) ? new(coeffs,model,mesh,Fil) : throw(DimensionMismatch("coeffs must be a row-vector"))
    end
end

size(d::SFMDistribution) = size(d.coeffs)
getindex(d::SFMDistribution,i::Int,j::Int) = d.coeffs[i,j]
setindex!(d::SFMDistribution,x,i::Int,j::Int) = throw(DomainError("inserted value(s) must be Float64/Int"))
setindex!(d::SFMDistribution,x::Float64,i::Int,j::Int) = (d.coeffs[i,j]=x)
setindex!(d::SFMDistribution,x::Int,i::Int,j::Int) = (d.coeffs[i,j]=convert(Float64,x))
*(u::SFMDistribution,B::AbstractArray{Float64,2}) = *(u.coeffs,B)
*(B::AbstractArray{Float64,2},u::SFMDistribution) = 
    (size(B,2)==1) ? *(B*u.coeffs) : throw(DimensionMismatch("u is a row-vector and B has more than 1 column"))

function _error_on_nothing(idx)
    (idx===nothing) && throw(DomainError("x is not in the support of the mesh"))
end

function _get_nodes_coeffs_from_index(cell_idx::Int,i::Int,mesh::Mesh,model::Model) 
    cell_nodes = CellNodes(mesh)[:,cell_idx]
    N₋ = sum(model.C.<=0)
    coeff_idx = (N₋ + (i-1)*TotalNBases(mesh) + (cell_idx-1)*NBases(mesh)) .+ (1:NBases(mesh))
    return cell_nodes, coeff_idx
end

function _get_coeff_index_pos(x::Float64,i::Int,mesh::Mesh,model::Model) 
    cell_idx = findlast(x.>=mesh.Nodes)
    _error_on_nothing(cell_idx)
    cell_nodes, coeff_idx = _get_nodes_coeffs_from_index(cell_idx,i,mesh,model)
    return cell_idx, cell_nodes, coeff_idx
end
function _get_coeff_index_neg(x::Float64,i::Int,mesh::Mesh,model::Model) 
    cell_idx = findfirst(x.<=mesh.Nodes) - 1
    _error_on_nothing(cell_idx)
    cell_nodes, coeff_idx = _get_nodes_coeffs_from_index(cell_idx,i,mesh,model)
    return cell_idx, cell_nodes, coeff_idx
end

function _get_point_mass_data_pos(i::Int,mesh::Mesh,model::Model)
    cell_nodes = mesh.Nodes[end]
    N₋ = sum(model.C.<=0)
    coeff_idx = N₋ + TotalNBases(mesh)*NPhases(model) + sum(model.C[1:i].>=0)
    return cell_nodes, coeff_idx 
end
function _get_point_mass_data_neg(i::Int,mesh::Mesh,model::Model)
    cell_nodes = mesh.Nodes[1]
    coeff_idx = sum(model.C[1:i].<=0)
    return cell_nodes, coeff_idx 
end
_is_left_point_mass(x::Float64,i::Int,mesh::Mesh,model::Model) = 
    (x==mesh.Nodes[1])&&(model.C[i]<=0)
_is_right_point_mass(x::Float64,i::Int,mesh::Mesh,model::Model) = 
    (x==mesh.Nodes[end])&&(model.C[i]>=0)
    

function _get_coeffs_index(x::Float64,i::Int,model::Model,mesh::Mesh)
    !(i∈phases(model)) && throw(DomainError("phase i must be in the support of the model"))

    # find which inteval Dₗ,ᵢ x is in 
    if _is_left_point_mass(x,i,mesh,model)
        cell_idx = "point mass"
        cell_nodes, coeff_idx = _get_point_mass_data_neg(i,mesh,model)
    elseif _is_right_point_mass(x,i,mesh,model)
        cell_idx = "point mass"
        cell_nodes, coeff_idx = _get_point_mass_data_pos(i,mesh,model)
    else # not a point mass 
        if model.C[i]>=0 
            cell_idx, cell_nodes, coeff_idx = _get_coeff_index_pos(x,i,mesh,model) 
        elseif model.C[i]<0 
            cell_idx, cell_nodes, coeff_idx = _get_coeff_index_neg(x,i,mesh,model) 
        end
    end

    return cell_idx, cell_nodes, coeff_idx
end

function legendre_to_lagrange(coeffs)
    order = length(coeffs)
    V = vandermonde(NBases(mesh))
    return V.V*coeffs
end

function pdf(d::SFMDistribution{T},model::Model) where T<:Mesh
    throw(DomainError("unknown SFMDistribution{<:Mesh}"))
end

function pdf(d::SFMDistribution{DGMesh},model::Model)
    function f(x::Float64,i::Int) # the PDF
        # check phase is in support 
        !(i∈phases(model)) && throw(DomainError("phase i must be in the support of the model"))
        # if x is not in the support return 0.0
        mesh = d.mesh
        if ((x<mesh.Nodes[1])||(x>mesh.Nodes[end]))
            fxi = 0.0
        else
            cell_idx, cell_nodes, coeff_idx = _get_coeffs_index(x,i,model,mesh)
            coeffs = d.coeffs[coeff_idx]
            # if not a point mass, then reconstruct solution
            if !(cell_idx=="point mass")
                if Basis(mesh) == "legendre"
                    coeffs = legendre_to_lagrange(coeffs)
                else
                    V = vandermonde(NBases(mesh))
                    coeffs = (2/(Δ(mesh)[cell_idx]))*(1.0./V.w).*coeffs
                end
                basis_values = lagrange_poly_basis(cell_nodes, x)
                fxi = LinearAlgebra.dot(basis_values,coeffs)
            else 
                fxi = coeffs
            end
        end
        return fxi
    end
    return f
end
pdf(d::SFMDistribution{T},model::Model,x,i) where T<:Mesh = 
    throw(DomainError("x must be Float64/Int/Array{Float64/Int,1}, i must be Int/Array{Int,1}"))
pdf(d::SFMDistribution{T},model::Model,x::Float64,i::Int) where T<:Mesh = pdf(d,model)(x,i)
pdf(d::SFMDistribution{T},model::Model,x::Int,i::Int) where T<:Mesh = pdf(d,model)(convert(Float64,x),i)
# pdf(d::SFMDistribution{T},model::Model,x::Array{Float64,1},i::Int) where T<:Mesh = pdf(d,model).(x,i)
# pdf(d::SFMDistribution{T},model::Model,x::Array{Float64,1},i::Array{Int,1}) where T<:Mesh = pdf(d,model).(x,i)

function pdf(d::SFMDistribution{FRAPMesh},model::Model)
    function f(x::Float64,i::Int) # the PDF
        # check phase is in support 
        !(i∈phases(model)) && throw(DomainError("phase i must be in the support of the model"))
        # if x is not in the support return 0.0
        mesh = d.mesh
        if ((x<mesh.Nodes[1])||(x>mesh.Nodes[end]))
            fxi = 0.0
        else
            cell_idx, cell_nodes, coeff_idx = _get_coeffs_index(x,i,model,mesh)
            coeffs = d.coeffs[coeff_idx]
            # if not a point mass, then reconstruct solution
            if !(cell_idx=="point mass")
                if model.C[i]>0
                    yₖ₊₁ = mesh.Nodes[cell_idx+1]
                    to_go = yₖ₊₁-x
                elseif model.C[i]<0
                    yₖ = mesh.Nodes[cell_idx]
                    to_go = x-yₖ
                end
                me = MakeME(CMEParams[NBases(mesh)], mean = Δ(mesh)[cell_idx])
                fxi = (pdf(Array(coeffs'),me,to_go) + pdf(Array(coeffs'),me,2*Δ(mesh)[cell_idx]-to_go))./cdf(Array(coeffs'),me,2*Δ(mesh)[cell_idx])
            else 
                fxi = coeffs
            end
        end
        return fxi
    end
    return f
end

function pdf(d::SFMDistribution{FVMesh},model::Model)
    function f(x::Float64,i::Int) # the PDF
        # check phase is in support 
        !(i∈phases(model)) && throw(DomainError("phase i must be in the support of the model"))
        # if x is not in the support return 0.0
        mesh = d.mesh
        if ((x<mesh.Nodes[1])||(x>mesh.Nodes[end]))
            fxi = 0.0
        else
            cell_idx, cell_nodes, coeff_idx = _get_coeffs_index(x,i,model,mesh)
            # if not a point mass, then reconstruct solution
            if !(cell_idx=="point mass")
                ptsLHS = Int(ceil(Order(mesh)/2))
                if cell_idx-ptsLHS < 0
                    nodesIdx = 1:Order(mesh)
                    nodes = CellNodes(mesh)[nodesIdx]
                    poly_vals = lagrange_poly_basis(nodes,x)
                elseif cell_idx-ptsLHS+Order(mesh) > TotalNBases(mesh)
                    nodesIdx = (TotalNBases(mesh)-Order(mesh)+1):TotalNBases(mesh)
                    nodes = CellNodes(mesh)[nodesIdx]
                    poly_vals = lagrange_poly_basis(nodes,x)
                else
                    nodesIdx =  (cell_idx-ptsLHS) .+ (1:Order(mesh))
                    poly_vals = lagrange_poly_basis(CellNodes(mesh)[nodesIdx],x)
                end
                coeff_idx = (sum(model.C.<=0) + (i-1)*TotalNBases(mesh)) .+ nodesIdx
                coeffs = d.coeffs[coeff_idx]#./Δ(mesh)[cell_idx]
                fxi = LinearAlgebra.dot(poly_vals,coeffs)
            else 
                coeffs = d.coeffs[coeff_idx]
                fxi = coeffs
            end
        end
        return fxi
    end
    return f
end

############
### CDFs ###
############

function cdf(d::SFMDistribution{T},model::Model) where T<:Mesh
    throw(DomainError("unknown SFMDistribution{<:Mesh}"))
end

"""

    _sum_cells_left(d::SFMDistribution, i::Int, cell_idx::Int, mesh::Mesh, model::Model)

Add up all the probability mass in phase `i` in the cells to the left of `cell_idx`.
"""
function _sum_cells_left(d::SFMDistribution, i::Int, cell_idx::Int, mesh::Mesh, model::Model)
    c = 0.0
    if Basis(mesh) == "legendre"
        for cell in 1:(cell_idx-1)
            # first legendre basis function =1 & has all the mass
            idx = (sum(model.C.<=0) + (i-1)*TotalNBases(mesh) + (cell-1)*NBases(mesh)) .+ 1 
            c += d.coeffs[idx]
        end
    else
        for cell in 1:(cell_idx-1)
            idx = (sum(model.C.<=0) + (i-1)*TotalNBases(mesh) + (cell-1)*NBases(mesh)) .+ (1:NBases(mesh))
            c += sum(d.coeffs[idx])
        end
    end
    return c
end

function cdf(d::SFMDistribution{DGMesh},model::Model)
    function F(x::Float64,i::Int) # the PDF
        # check phase is in support 
        !(i∈phases(model)) && throw(DomainError("phase i must be in the support of the model"))
        mesh = d.mesh
        Fxi = 0.0
        if (x<mesh.Nodes[1])
            # Fxi = 0.0
        else
            # Fxi = 0.0
            # left pm
            if (x>=mesh.Nodes[1])&&(model.C[i]<=0)
                ~, left_pm_idx = _get_point_mass_data_neg(i,mesh,model)
                left_pm = d.coeffs[left_pm_idx]
                Fxi += left_pm
            end
            # integral over density
            (x.>=mesh.Nodes[end]) ? (xd=mesh.Nodes[end]-sqrt(eps())) : xd = x
            cell_idx, ~, ~ = _get_coeffs_index(xd,i,model,mesh)
            if !(cell_idx=="point mass")
                # add all mass from cells to the left
                Fxi += _sum_cells_left(d, i, cell_idx, mesh, model)

                # integrate up to x in the cell which contains x
                temp_pdf(y) = pdf(d,model)(y,i)
                quad = gauss_lobatto_quadrature(temp_pdf,mesh.Nodes[cell_idx]+sqrt(eps()),xd,NBases(mesh))
                Fxi += quad
            end
            # add the RH point mass if  required
            if (x>=mesh.Nodes[end])&&(model.C[i]>=0)
                ~, ~, right_pm_idx = _get_coeffs_index(mesh.Nodes[end],i,model,mesh)
                right_pm = d.coeffs[right_pm_idx]
                Fxi += right_pm
            end
        end
        return Fxi
    end
    return F
end
cdf(d::SFMDistribution{T},model::Model,x,i) where T<:Mesh = 
    throw(DomainError("x must be Float64/Int/Array{Float64/Int,1}, i must be Int/Array{Int,1}"))
cdf(d::SFMDistribution{T},model::Model,x::Float64,i::Int) where T<:Mesh = cdf(d,model)(x,i)
cdf(d::SFMDistribution{T},model::Model,x::Int,i::Int) where T<:Mesh = cdf(d,model)(convert(Float64,x),i)

function cdf(d::SFMDistribution{FRAPMesh},model::Model)
    function F(x::Float64,i::Int) # the PDF
        # check phase is in support 
        !(i∈phases(model)) && throw(DomainError("phase i must be in the support of the model"))
        # if x is not in the support return 0.0
        mesh = d.mesh
        if (x<mesh.Nodes[1])
            Fxi = 0.0
        else
            Fxi = 0.0
            # left pm
            if (x>=mesh.Nodes[1])&&(model.C[i]<=0)
                ~, ~, left_pm_idx = _get_coeffs_index(mesh.Nodes[1],i,model,mesh)
                left_pm = d.coeffs[left_pm_idx]
                Fxi += left_pm
            end
            # integral over density
            (x.>=mesh.Nodes[end]) ? (xd=mesh.Nodes[end]-sqrt(eps())) : xd = x
            cell_idx, cell_nodes, coeff_idx = _get_coeffs_index(xd,i,model,mesh)
            coeffs = d.coeffs[coeff_idx]

            if !(cell_idx=="point mass")
                # add all mass from cells to the left
                Fxi += _sum_cells_left(d, i, cell_idx, mesh, model)
                
                # integrate up to x in the cell which contains x
                me = MakeME(CMEParams[NBases(mesh)], mean = Δ(mesh)[cell_idx])
                a = Array(coeffs')
                if model.C[i]>=0
                    yₖ₊₁ = mesh.Nodes[cell_idx+1]
                    Fxi += (ccdf(a,me,yₖ₊₁-x) - ccdf(a,me,2*Δ(mesh)[cell_idx]-(yₖ₊₁-x)))/(cdf(a,me,2*Δ(mesh)[cell_idx]))
                elseif model.C[i]<0
                    yₖ = mesh.Nodes[cell_idx]
                    Fxi += sum(a) - (ccdf(a,me,x-yₖ) - ccdf(a,me,2*Δ(mesh)[cell_idx]-(x-yₖ)))/(cdf(a,me,2*Δ(mesh)[cell_idx]))
                end
            end
            if (x>=mesh.Nodes[end])&&(model.C[i]>=0)
                ~, ~, right_pm_idx = _get_coeffs_index(mesh.Nodes[end],i,model,mesh)
                right_pm = d.coeffs[right_pm_idx]
                Fxi += right_pm
            end
        end
        return Fxi
    end
    return F
end

function _sum_cells_left_fv(d, i, cell_idx, mesh, model)
    c = 0
    for cell in 1:(cell_idx-1)
        # first legendre basis function =1 & has all the mass
        idx = sum(model.C.<=0) + (i-1)*TotalNBases(mesh) + cell
        c += d.coeffs[idx]*Δ(mesh)[cell]
    end
    return c
end

function cdf(d::SFMDistribution{FVMesh},model::Model)
    function F(x::Float64,i::Int) # the PDF
        # check phase is in support 
        !(i∈phases(model)) && throw(DomainError("phase i must be in the support of the model"))
        # if x is not in the support return 0.0
        mesh = d.mesh
        Fxi = 0.0
        if (x<mesh.Nodes[1])
            # Fxi = 0.0
        else
            # Fxi = 0.0
            # left pm
            if (x>=mesh.Nodes[1])&&(model.C[i]<=0)
                ~, ~, left_pm_idx = _get_coeffs_index(mesh.Nodes[1],i,model,mesh)
                left_pm = d.coeffs[left_pm_idx]
                Fxi += left_pm
            end
            # integral over density
            (x.>=mesh.Nodes[end]) ? (xd=mesh.Nodes[end]-sqrt(eps())) : xd = x
            cell_idx, cell_nodes, coeff_idx = _get_coeffs_index(xd,i,model,mesh)
            # if not a point mass, then reconstruct solution
            if !(cell_idx=="point mass")
                # add all mass from cells to the left
                Fxi += _sum_cells_left_fv(d, i, cell_idx, mesh, model)

                # integrate up to x in the cell which contains x
                temp_pdf(y) = pdf(d,model)(y,i)
                quad = gauss_lobatto_quadrature(temp_pdf,mesh.Nodes[cell_idx]+sqrt(eps()),xd,Order(mesh))
                Fxi += quad 
            end
            if (x>=mesh.Nodes[end])&&(model.C[i]>=0)
                ~, ~, right_pm_idx = _get_coeffs_index(mesh.Nodes[end],i,model,mesh)
                right_pm = d.coeffs[right_pm_idx]
                Fxi += right_pm
            end
        end
        return Fxi
    end
    return F
end

abstract type SFFMDistribution end

"""

    SFFMDistribution(
        pm::Array{<:Real},
        distribution::Array{<:Real,3},
        x::Array{<:Real},
        type::String,
    )

- `pm::Array{Float64}`: a vector containing the point masses, the first
    `sum(model.C.<=0)` entries are the left hand point masses and the last
    `sum(model.C.>=0)` are the right-hand point masses.
- `distribution::Array{Float64,3}`: "probability" or "density"` 
- `x::Array{Float64,2}`:
    - if `type="probability"` is a `1×NIntervals×NPhases` array
        containing the cell centers.
    - if `type="density"` is a `NBases×NIntervals×NPhases` array
        containing the cell nodes at which the denisty is evaluated.
- `type::String`: either `"probability"` or `"density"`. `"cumulative"` is
    not possible.
"""
struct SFFMDensity <: SFFMDistribution
    pm::Array{<:Real}
    distribution::Array{<:Real,3}
    x::Array{<:Real}
end
struct SFFMProbability <: SFFMDistribution
    pm::Array{<:Real}
    distribution::Array{<:Real,3}
    x::Array{<:Real}
end
struct SFFMCDF <: SFFMDistribution
    pm::Array{<:Real}
    distribution::Array{<:Real,3}
    x::Array{<:Real}
end

"""
Convert from a vector of coefficients for the DG system to a distribution.

    Coeffs2Dist(
        model::SFFM.Model,
        mesh::SFFM.Mesh,
        Coeffs;
        type::String = "probability",
    )

# Arguments
- `model`: a Model object
- `mesh`: a Mesh object as output from MakeMesh
- `Coeffs::Array`: a vector of coefficients from the DG method
- `type::String`: an (optional) declaration of what type of distribution you
    want to convert to. Options are `"probability"` to return the probabilities
    ``P(X(t)∈ D_k, φ(t) = i)`` where ``D_k``is the kth cell, `"cumulative"` to
    return the CDF evaluated at cell edges, or `"density"` to return an
    approximation to the density ar at the SFFM.CellNodes(mesh).

# Output
- a tuple with keys
(pm=pm, distribution=yvals, x=xvals, type=type)
    - `pm::Array{Float64}`: a vector containing the point masses, the first
        `sum(model.C.<=0)` entries are the left hand point masses and the last
        `sum(model.C.>=0)` are the right-hand point masses.
    - `distribution::Array{Float64,3}`:
        - if `type="cumulative"` returns a `2×NIntervals×NPhases` array
            containing the CDF evaluated at the cell edges as contained in
            `x` below. i.e. `distribution[1,:,i]` returns the cdf at the
            left-hand edges of the cells in phase `i` and `distribution[2,:,i]`
            at the right hand edges.
        - if `type="probability"` returns a `1×NIntervals×NPhases` array
            containing the probabilities ``P(X(t)∈ D_k, φ(t) = i)`` where ``D_k``
            is the kth cell.
        - if `type="density"` returns a `NBases×NIntervals×NPhases` array
            containing the density function evaluated at the cell nodes as
            contained in `x` below.
    - `x::Array{Float64,2}`:
        - if `type="cumulative"` returns a `2×NIntervals×NPhases` array
            containing the cell edges as contained. i.e. `x[1,:]`
            returns the left-hand edges of the cells and `x[2,:]` at the
            right-hand edges.
        - if `type="probability"` returns a `1×NIntervals×NPhases` array
            containing the cell centers.
        - if `type="density"` returns a `NBases×NIntervals×NPhases` array
            containing the cell nodes.
    - `type`: as input in arguments.
"""
function Coeffs2Dist(
    model::SFFM.Model,
    mesh::SFFM.DGMesh,
    Coeffs::AbstractArray,
    type::Type{T} = SFFMProbability,
    v::Bool = false,
) where {T<:SFFMDistribution} 

    V = SFFM.vandermonde(NBases(mesh))
    N₋ = sum(model.C .<= 0)
    N₊ = sum(model.C .>= 0)

    if type == SFFMDensity
        xvals = SFFM.CellNodes(mesh)
        if Basis(mesh) == "legendre"
            yvals = reshape(Coeffs[N₋+1:end-N₊], NBases(mesh), NIntervals(mesh), NPhases(model))
            for i in 1:NPhases(model)
                yvals[:,:,i] = V.V * yvals[:,:,i]
            end
            pm = [Coeffs[1:N₋]; Coeffs[end-N₊+1:end]]
        elseif Basis(mesh) == "lagrange"
            yvals =
                Coeffs[N₋+1:end-N₊] .* repeat(1.0 ./ V.w, NIntervals(mesh) * NPhases(model)) .*
                (repeat(2.0 ./ Δ(mesh), 1, NBases(mesh) * NPhases(model))'[:])
            yvals = reshape(yvals, NBases(mesh), NIntervals(mesh), NPhases(model))
            pm = [Coeffs[1:N₋]; Coeffs[end-N₊+1:end]]
        end
        if NBases(mesh) == 1
            yvals = [1;1].*yvals
            xvals = [SFFM.CellNodes(mesh)-Δ(mesh)'/2;SFFM.CellNodes(mesh)+Δ(mesh)'/2]
        end
    elseif type == SFFMProbability
        if NBases(mesh) > 1 
            xvals = SFFM.CellNodes(mesh)[1, :] + (Δ(mesh) ./ 2)
        else
            xvals = SFFM.CellNodes(mesh)
        end
        if Basis(mesh) == "legendre"
            yvals = (reshape(Coeffs[N₋+1:NBases(mesh):end-N₊], 1, NIntervals(mesh), NPhases(model)).*Δ(mesh)')./sqrt(2)
            pm = [Coeffs[1:N₋]; Coeffs[end-N₊+1:end]]
        elseif Basis(mesh) == "lagrange"
            yvals = sum(
                reshape(Coeffs[N₋+1:end-N₊], NBases(mesh), NIntervals(mesh), NPhases(model)),
                dims = 1,
            )
            pm = [Coeffs[1:N₋]; Coeffs[end-N₊+1:end]]
        end
    elseif type == SFFMCDF
        if NBases(mesh) > 1 
            xvals = SFFM.CellNodes(mesh)[[1;end], :]
        else
            xvals = [SFFM.CellNodes(mesh)-Δ(mesh)'/2;SFFM.CellNodes(mesh)+Δ(mesh)'/2]
        end
        if Basis(mesh) == "legendre"
            tempDist = (reshape(Coeffs[N₋+1:NBases(mesh):end-N₊], 1, NIntervals(mesh), NPhases(model)).*Δ(mesh)')./sqrt(2)
            pm = [Coeffs[1:N₋]; Coeffs[end-N₊+1:end]]
        elseif Basis(mesh) == "lagrange"
            tempDist = sum(
                reshape(Coeffs[N₋+1:end-N₊], NBases(mesh), NIntervals(mesh), NPhases(model)),
                dims = 1,
            )
            pm = [Coeffs[1:N₋]; Coeffs[end-N₊+1:end]]
        end
        tempDist = cumsum(tempDist,dims=2)
        temppm = zeros(Float64,1,2,NPhases(model))
        temppm[:,1,model.C.<=0] = pm[1:N₋]
        temppm[:,2,model.C.>=0] = pm[N₊+1:end]
        yvals = zeros(Float64,2,NIntervals(mesh),NPhases(model))
        yvals[1,2:end,:] = tempDist[1,1:end-1,:]
        yvals[2,:,:] = tempDist
        yvals = yvals .+ reshape(temppm[1,1,:],1,1,NPhases(model))
        pm[N₋+1:end] = pm[N₋+1:end] + yvals[end,end,model.C.>=0]
    end
    
    out = type(pm, yvals, xvals)
    v && println("UPDATE: distribution object created with keys ", fieldnames(type))
    return out
end
function Coeffs2Dist(
    model::SFFM.Model,
    mesh::Union{FRAPMesh, FVMesh},
    Coeffs::AbstractArray,
    type::Type{T} = SFFMProbability,
    v::Bool = false,
) where {T<:SFFMDistribution}

    if type != SFFMProbability
        args = [
            model;
            mesh;
            Coeffs;
            type;
        ]
        error("Input Error: no functionality other than 'probability' implemented, yet...")
    end
    
    N₋ = sum(model.C .<= 0)
    N₊ = sum(model.C .>= 0)
    
    xvals = SFFM.CellNodes(mesh)
    
    yvals = sum(
        reshape(Coeffs[N₋+1:end-N₊], NBases(mesh), NIntervals(mesh), NPhases(model)),
        dims = 1,
    )
    pm = [Coeffs[1:N₋]; Coeffs[end-N₊+1:end]]

    out = type(pm, yvals, xvals)
    v && println("UPDATE: distribution object created with keys ", fieldnames(type))
    return out
end

"""
Converts a distribution as output from `Coeffs2Dist()` to a vector of DG
coefficients.

    Dist2Coeffs(
        model::SFFM.Model,
        mesh::SFFM.Mesh,
        Distn::SFFMDistribution,
    )

# Arguments
- `model`: a Model object
- `mesh`: a Mesh object as output from MakeMesh
- `Distn::SFFMDistribution
    - if `type="probability"` is a `1×NIntervals×NPhases` array containing
        the probabilities ``P(X(t)∈ D_k, φ(t) = i)`` where ``D_k``
        is the kth cell.
    - if `type="density"` is a `NBases×NIntervals×NPhases` array containing
        either the density function evaluated at the cell nodes which are in
        `x` below, or, the inner product of the density function against the
        lagrange polynomials.

# Output
- `coeffs` a row vector of coefficient values of length
    `TotalNBases*NPhases + N₋ + N₊` ordered according to LH point masses, RH
    point masses, interior basis functions according to basis function, cell,
    phase. Used to premultiply operators such as B from `MakeB()`
"""
function Dist2Coeffs(
    model::SFFM.Model,
    mesh::SFFM.DGMesh,
    Distn::SFFMDensity,
)
    V = SFFM.vandermonde(NBases(mesh))
    theDistribution =
        zeros(Float64, NBases(mesh), NIntervals(mesh), NPhases(model))
    if Basis(mesh) == "legendre"
        theDistribution = Distn.distribution
        for i = 1:NPhases(model)
            theDistribution[:, :, i] = V.inv * theDistribution[:, :, i]
        end
    elseif Basis(mesh) == "lagrange"
        theDistribution .= Distn.distribution
        # convert to probability coefficients by multiplying by the
        # weights in V.w/2 and cell widths Δ
        theDistribution = ((V.w .* theDistribution).*(Δ(mesh) / 2)')[:]
    end
    # also put the point masses on the ends
    coeffs = [
        Distn.pm[1:sum(model.C .<= 0)]
        theDistribution[:]
        Distn.pm[sum(model.C .<= 0)+1:end]
    ]
    coeffs = Matrix(coeffs[:]')
    return coeffs
end

function Dist2Coeffs(
    model::SFFM.Model,
    mesh::SFFM.DGMesh,
    Distn::SFFMProbability,
)
    V = SFFM.vandermonde(NBases(mesh))
    theDistribution =
        zeros(Float64, NBases(mesh), NIntervals(mesh), NPhases(model))
    if Basis(mesh) == "legendre"
        # for the legendre basis the first basis function is ϕ(x)=Δ√2 and
        # all other basis functions are orthogonal to this. Hence, we map
        # the cell probabilities to the first basis function only.
        theDistribution[1, :, :] = Distn.distribution./Δ(mesh)'.*sqrt(2)
    elseif Basis(mesh) == "lagrange"
        theDistribution .= Distn.distribution
        # convert to probability coefficients by multiplying by the
        # weights in V.w/2
        theDistribution = (V.w .* theDistribution / 2)[:]
    end
    # also put the point masses on the ends
    coeffs = [
        Distn.pm[1:sum(model.C .<= 0)]
        theDistribution[:]
        Distn.pm[sum(model.C .<= 0)+1:end]
    ]
    coeffs = Matrix(coeffs[:]')
    return coeffs
end
function Dist2Coeffs(
    model::SFFM.Model,
    mesh::Union{SFFM.FRAPMesh,SFFM.FVMesh},
    Distn::SFFMDistribution
)
    
    # also put the point masses on the ends
    coeffs = [
        Distn.pm[1:sum(model.C .<= 0)]
        Distn.distribution[:]
        Distn.pm[sum(model.C .<= 0)+1:end]
    ]
    
    coeffs = Matrix(coeffs[:]')
    return coeffs
end

"""
Computes the error between distributions.

    starSeminorm(d1::SFFMProbability, d2::SFFMProbability)

# Arguments
- `d1`: a distribution object as output from `Coeffs2Dist` 
- `d2`: a distribution object as output from `Coeffs2Dist` 
"""
function starSeminorm(d1::SFFMProbability, d2::SFFMProbability)
    e = sum(abs.(d1.pm-d2.pm)) + sum(abs.(d1.distribution-d2.distribution))
    return e
end
