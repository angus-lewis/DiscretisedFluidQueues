module DiscretisedFluidQueues

import Jacobi, LinearAlgebra, SparseArrays, StaticArrays
import Base: *, size, show, getindex, +, -, setindex!

# Types
export Model, DiscretisedFluidQueue, FluidQueue, Phase, PhaseSet # Queues are <:Model
export AbstractMatrixExponential, ConcentratedMatrixExponential, MatrixExponential 
export Mesh, DGMesh, FRAPMesh, FVMesh # are <:Mesh
export Generator, FullGenerator, LazyGenerator # are <:Generator
export SFMDistribution
export TimeIntegrationScheme, Euler, RungeKutta4 # Euler, RungeKutta4 <: TimeIntegrationScheme
export Simulation

# Functions 
export augment_model, membership, N₋, N₊, n_phases, phases, rates # Model methods 
export cell_nodes, Δ, n_bases_per_cell, n_bases_per_phase, n_intervals, total_n_bases # Mesh methods 
export interior_point_mass, left_point_mass, right_point_mass, integrate_time # SFMDistribution methods
export simulate, fixed_time, n_jumps, first_exit_x # Simulation methods
export build_lazy_generator, build_full_generator
export psi_fun_x, xi_x, stationary_distribution_x
export cme_params, pdf, ccdf, cdf, build_me

# model
include("1_SFM.jl")

include("2_abstract_mesh.jl") # things which apply to all meshs
include("2a_discretised_fluid_queue.jl")
include("3_lazy_generators.jl")
include("4_full_generators.jl")
include("5_SFM_operators.jl")

# auxillary functions
include("6_ME_tools.jl") # used in FRAPApproximation.jl
include("7_polynomials.jl") # used in discontinuous_Galerkin.jl

include("8_discontinuous_Galerkin.jl")
include("9_finite_volume_method.jl")
include("10_FRAP_approximation.jl")

include("11_distributions.jl")

include("12_time_integration.jl")

include("13_simulate.jl")

end