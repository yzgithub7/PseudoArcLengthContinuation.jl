using IterativeSolvers, KrylovKit, Parameters

# In this file, we regroud a way to provide linear solver for the Package

abstract type AbstractLinearSolver end

# The function linsolve(y, J, x) must return whether the solve was successfull and how many steps were required for the solve

####################################################################################################
# Solvers for default \ operator (backslash)
####################################################################################################
"""
The struct `Default` is used to  provide the backslash operator to our Package
"""
struct DefaultLS <: AbstractLinearSolver end

function (l::DefaultLS)(J, rhs)
	return J \ rhs, true, 1
end

# this function is used to solve (J + shift I) * x = rhs
# this is only used for the Hopf Newton / Continuation
function (l::DefaultLS)(J, rhs, shift::R) where {R <: Number}
	if shift == R(0)
		return J \ rhs, true, 1
	else
		return (J + shift * I) \ rhs, true, 1
	end
end
####################################################################################################
# Solvers for IterativeSolvers
####################################################################################################
@with_kw mutable struct GMRES_IterativeSolvers{T, Tl, Tr} <: AbstractLinearSolver
	tol::T = T(1e-4)		# tolerance for solver
	restart::Int64 = 200	# number of restarts
	maxiter::Int64 = 100
	N = 0					# dimension of the problem
	verbose = false
	log = true
	initially_zero = true
	Pl::Tl = IterativeSolvers.Identity()
	Pr::Tr = IterativeSolvers.Identity()
end

# this function is used to solve (J + shift I) * x = rhs
# the optional shift is only used for the Hopf Newton / Continuation
function (l::GMRES_IterativeSolvers{T, Tl, Tr})(J, rhs, shift::Ts = T(0)) where {T, Ts, Tl, Tr}
	# no need to use fancy axpy! here because IterativeSolvers "only" handles AbstractArray
	J_map = v -> apply(J, v) .+ shift .* v
	Jmap = LinearMap{Ts}(J_map, l.N, l.N ; ismutating = false)
	res = IterativeSolvers.gmres(Jmap, rhs, tol = l.tol, log = l.log, verbose = l.verbose, restart = l.restart, maxiter = l.maxiter, initially_zero = l.initially_zero, Pl = l.Pl, Pr = l.Pr)
	(res[2].iters >= l.maxiter) && (@warn "IterativeSolvers.gmres iterated maxIter =$(res[2].iters) times without achieving the desired tolerance.\n")
	return res[1], length(res) > 1, res[2].iters
end

####################################################################################################
# Solvers for KrylovKit
####################################################################################################
@with_kw mutable struct GMRES_KrylovKit{T} <: AbstractLinearSolver
	dim::Int64 = KrylovDefaults.krylovdim # Krylov Dimension
	atol::T  = T(KrylovDefaults.tol)	  # absolute tolerance for solver
	rtol::T  = T(KrylovDefaults.tol)	  # relative tolerance for solver
	restart::Int64 = 200				  # number of restarts
	maxiter::Int64 = KrylovDefaults.maxiter
	verbose::Int = 0
	issymmetric = false					# if the linear map is symmetric, only meaningful if T<:Real
	ishermitian = false 				# if the linear map is hermitian
	isposdef    = false 				# if the linear map is positive definite
end

function (l::GMRES_KrylovKit{T})(J, rhs) where T
	res, info = KrylovKit.linsolve(J, rhs, rtol = l.rtol, verbosity = l.verbose, krylovdim = l.dim, maxiter = l.maxiter, atol = l.atol, issymmetric = l.issymmetric, ishermitian = l.ishermitian, isposdef = l.isposdef)
	info.converged == 0 && (@warn "GMRES solver did not converge")
	return res, true, info.numiter
end

# this function is used to solve (J + shift I) * x = rhs
# this is only used for the Hopf Newton / Continuation
# function (l::GMRES_KrylovKit{T})(J, rhs, shift::Ts) where {T, Ts}
#	 @assert 1==0 "WIP"
#	 res, info = KrylovKit.linsolve(J, rhs, rtol = l.rtol, verbosity = l.verbose, krylovdim = l.dim, maxiter = l.maxiter, atol = l.atol)
#	 return res, true, info.numiter
# end
