"""
    ExplicitRungeKuttaScheme(
        step_size::Float64,
        alpha::LinearAlgebra.LowerTriangular{Float64},
        beta::LinearAlgebra.LowerTriangular{Float64},
    )

Generic data container for ExplicitRungeKuttaScheme for use in `integrate_time`.

We are interested in numerically integrating ODEs of the form
    ``a'(t) = a(t) Q``

where ``a(t)`` is a vector of coefficients and ``Q`` is a matrix, given an initial condition ``a(0)``. 

In this context, Explicit Runge-Kutta methods with ``s`` stages can be written as 

``v^{(0)} = a(t),``

``v^{(l)} = \\sum_{k=0}^{l-1} \\alpha_{l k} v^{(k)} + h\\beta_{l k}  v^{(k)} Q,\\, l = 1,...,s,``

``a(t+h) =v^{(s)},``

where ``h`` is the step-size and ``\\alpha_{l k}`` and ``\\beta_{l k}`` are parameters which define the scheme. 

# Arguments 
-  `step_size::Float64`: the step size of the integration scheme.
-  `alpha::LinearAlgebra.LowerTriangular{Float64}`: coefficients as described above 
-  `beta::LinearAlgebra.LowerTriangular{Float64}`: coefficients as described above 
"""
struct ExplicitRungeKuttaScheme
    step_size::Float64
    alpha::LinearAlgebra.LowerTriangular{Float64}
    beta::LinearAlgebra.LowerTriangular{Float64}
    function ExplicitRungeKuttaScheme(step_size::Float64,
        alpha::LinearAlgebra.LowerTriangular{Float64},
        beta::LinearAlgebra.LowerTriangular{Float64})

        t1 = (step_size > 0)
        checksquare(alpha)
        l1 = size(alpha)
        l2 = size(beta)
        (!t1)&&throw(DomainError("step_size must be positive"))
        !(l1==l2)&&throw(DimensionMismatch("alpha, beta must have same size"))
        return new(step_size,alpha,beta)
    end
end

"""
    ForwardEuler(step_size::Float64) <: ExplicitRungeKuttaScheme

Defines an Euler integration scheme to be used in `integrate_time`.

# Arguments 
-  `step_size::Float64`: the step size of the integration scheme.
"""
ForwardEuler(step_size::Float64) = ExplicitRungeKuttaScheme(
        step_size,
        LinearAlgebra.LowerTriangular([1.0][:,:]),
        LinearAlgebra.LowerTriangular([1.0][:,:])
    )

"""

    Heuns(step_size::Float64) <: ExplicitRungeKuttaScheme

Defines Heuns integration scheme to be used in `integrate_time`.

# Arguments 
-  `step_size::Float64`: the step size of the integration scheme.
"""
Heuns(step_size::Float64) = ExplicitRungeKuttaScheme(
        step_size,
        LinearAlgebra.LowerTriangular([1.0 0.0; 0.5 0.5]),
        LinearAlgebra.LowerTriangular([1.0 0.0; 0.0 0.5])
    )

"""

    StableRK3(step_size::Float64) <: ExplicitRungeKuttaScheme

Defines a strong stability preserving Runge-Kutta integration scheme to be used in `integrate_time`.

# Arguments 
-  `step_size::Float64`: the step size of the integration scheme.

Hesthaven, J. S. & Warburton, T. (2007), Nodal discontinuous Galerkin methods: algorithms, analysis, and applications, Springer Science & Business Media.
(Section 5.7)

"""
StableRK3(step_size::Float64) = ExplicitRungeKuttaScheme(
        step_size,
        LinearAlgebra.LowerTriangular([1.0 0.0 0.0; 0.75 0.25 0.0; 1/3 0.0 2/3]),
        LinearAlgebra.LowerTriangular([1.0 0.0 0.0; 0.0 0.25 0.0; 0.0 0.0 2/3])
    )
                
_α = [  1.0                0.0                 0.0                 0.0                 0.0                 ;
        0.44437049406734   0.55562950593266    0.0                 0.0                 0.0                 ;
        0.62010185138540   0.0                 0.37989814861460    0.0                 0.0                 ;
        0.17807995410773   0.0                 0.0                 0.82192004589227    0.0                 ;
        0.00683325884039   0.0                 0.51723167208978    0.12759831133288    0.34833675773694    ]
_β = [  0.39175222700392    0.0                 0.0                 0.0                 0.0                 ;
        0.0                 0.36841059262959    0.0                 0.0                 0.0                 ;
        0.0                 0.0                 0.25189177424738    0.0                 0.0                 ;
        0.0                 0.0                 0.0                 0.54497475021237    0.0                 ;
        0.0                 0.0                 0.0                 0.08460416338212    0.22600748319395    ]
"""
    StableRK4(step_size::Float64) = ExplicitRungeKuttaScheme(
            step_size,
            LinearAlgebra.LowerTriangular(_α),
            LinearAlgebra.LowerTriangular(_β)
        )

Defines a strong stability preserving Runge-Kutta integration scheme to be used in `integrate_time`.

# Arguments 
-  `step_size::Float64`: the step size of the integration scheme.

Raymond J. Spiteri and Steven J. Ruuth. A new class of optimal high-order
strong-stability-preserving time discretization methods. SIAM J. Numer. Anal.,
40(2):469-491, 2002.

Hesthaven, J. S. & Warburton, T. (2007), Nodal discontinuous Galerkin methods: algorithms, analysis, and applications, Springer Science & Business Media.
(Section 5.7)
"""
StableRK4(step_size::Float64) = ExplicitRungeKuttaScheme(
        step_size,
        LinearAlgebra.LowerTriangular(_α),
        LinearAlgebra.LowerTriangular(_β)
    )

"""
Given `x0` and `D` apprximate `x0 exp(Dy)`.

    integrate_time(x0::Array{Float64,2}, D::AbstractArray{Float64,2},
        y::Float64, scheme::ExplicitRungeKuttaScheme [; limiter])

# Arguments
- `x0`: An initial vector
- `D`: A square matrix
- `y`: time to integrate up to
- `h`: ExplicitRungeKuttaScheme.
- `limiter`: optional named argument spacifying the slope-limiter to used. The 
    limiter function will be applied at every stage and every time-step of the 
    ExplicitRungeKuttaScheme. 
"""
function integrate_time(x0::Array{Float64,2}, D::AbstractArray{Float64,2},
    y::Float64, scheme::ExplicitRungeKuttaScheme)

    checksquare(D)
    !(size(x0,2)==size(D,1))&&throw(DimensionMismatch("x0 must have length size(D,1)"))
    
    return _integrate(x0[:],D,y,scheme)
end
function integrate_time(x0::Array{Float64,1}, D::AbstractArray{Float64,2},
    y::Float64, scheme::ExplicitRungeKuttaScheme)

    checksquare(D)
    
    return _integrate(x0,D,y,scheme)
end

function integrate_time(x0::SFMDistribution, D::AbstractArray{Float64,2},
    y::Float64, scheme::ExplicitRungeKuttaScheme)   
    return SFMDistribution(integrate_time(x0.coeffs,D,y,scheme),x0.dq)
end

function integrate_time(x0::SFMDistribution{DGMesh{T}}, D::AbstractArray{Float64,2},
    y::Float64, scheme::ExplicitRungeKuttaScheme; limiter::Limiter=GeneralisedMUSCL) where T

    checksquare(D)
    
    limiter_params = limiter.generate_params(x0.dq)
    limiter_function = x->limiter.fun(x,limiter_params...)

    return SFMDistribution(_integrate(x0.coeffs,D,y,scheme,limiter_function),x0.dq)
end

"""
    _integrate(x0::Array{Float64,1}, 
        D::Union{Array{Float64,2},SparseArrays.SparseMatrixCSC{Float64,Int}}, 
        y::Float64, scheme::ExplicitRungeKuttaScheme)

Use ExplicitRungeKuttaScheme method.
"""
function _integrate(x0::Array{Float64,1}, D::AbstractArray{Float64,2},
    y::Float64, scheme::ExplicitRungeKuttaScheme)

    return _integrate(x0, D, y, scheme, identity)
end

function _integrate(x0::Array{Float64,1}, D::AbstractArray{Float64,2},
    y::Float64, scheme::ExplicitRungeKuttaScheme, limit_function::Function)
    
    x = limit_function(x0)
    h = scheme.step_size
    l = size(scheme.alpha,1)
    α = scheme.alpha
    βh = scheme.beta*h
    v = Array{Float64,2}(undef,length(x0),l+1)
    vD = Array{Float64,2}(undef,length(x0),l+1)
    for t = h:h:y
        v[:,1] = x
        for i in 1:l
            vD[:,i] = transpose(v[:,i])*D
            initialised = false 
            for j in 1:i
                if α[i,j]!=0.0
                    initialised ? (v[:,i+1]+=v[:,j]*α[i,j]) : (v[:,i+1]=v[:,j]*α[i,j]; initialised=true)
                end
                if βh[i,j]!=0.0
                    initialised ? (v[:,i+1]+=vD[:,j]*βh[i,j]) : (v[:,i+1]=vD[:,j]*βh[i,j]; initialised=true)
                end
            end
            v[:,i+1] = limit_function(v[:,i+1])
        end
        x = v[:,end]
    end
    return x
end
