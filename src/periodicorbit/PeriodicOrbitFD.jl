using BlockArrays, SparseArrays
# This file implements some Finite Differences methods to locate periodic orbits

####################################################################################################
# method using the Trapezoidal rule (Order 2 in time) and discretisation of the periodic orbit. This is not a shooting method!

"""
	pb = PeriodicOrbitTrap(F, J, ϕ, xπ, M::Int, linsolve)
This structure implements Finite Differences based on Trapezoidal rule to locate periodic orbits. The arguements are as follows
- F vector field
- J jacobian of the vector field
- ϕ used for the Poincare section
- xπ used for the Poincare section
- M::Int number of slices in [0,2π]
- linsolve <: AbstractLinearSolver  linear solver

You can then call pb(orbitguess) to apply the functional to a guess. Note that orbitguess must be of size M * N + 1 where N is the number of unknowns in the state space and `orbitguess[M*N+1]` is an estimate of the period of the limit cycle.

The scheme is as follows, one look for `T = x[end]` and
 ``x_{i+1} - x_{i} - \\frac{h}{2} \\left(F(x_{i+1}) + F(x_i)\\right) = 0``

where `h = T/M`. Finally, the phase of the periodic orbit is constraint by

 ``\\langle x[1] - x\\pi, \\phi\\rangle.``

"""
@with_kw struct PeriodicOrbitTrap{TF, TJ, vectype, S <: AbstractLinearSolver} <: PeriodicOrbit
	# Function F(x, p) = 0
	F::TF

	# Jacobian of F wrt x
	J::TJ

	# variables to define a Poincare Section
	ϕ::vectype
	xπ::vectype

	# discretisation of the time interval
	M::Int = 100

	linsolver::S
end

"""
This encodes the previous functional for finding periodic orbits based on finite differences using the Trapezoidal rule
"""
function (poPb::PeriodicOrbitTrap{TF, TJ, vectype, S})(u0::vectype) where {TF, TJ, vectype <: AbstractVector, S}
	M = poPb.M
	N = div(length(u0) - 1, M)
	T = u0[end]
	h = T / M

	u0c = reshape(u0[1:end-1], N, M)
	outc = similar(u0c)
	for ii=2:M
		outc[:, ii] .= (u0c[:, ii] .- u0c[:, ii-1]) .- h/2 .* (poPb.F(u0c[:, ii]) .+ poPb.F(u0c[:, ii-1]))
	end

	# closure condition ensuring a periodic orbit
	outc[:, 1] .= u0c[:, M] .- u0c[:, 1]

	return vcat(vec(outc),
			dot(u0c[:, 1] .- poPb.xπ, poPb.ϕ)) # this is the phase condition
end

"""
Matrix free expression of the Jacobian of the problem for computing periodic obits when evaluated at `u0` and applied to `du`.
"""
function (poPb::PeriodicOrbitTrap{TF, TJ, vectype, S})(u0::vectype, du) where {TF, TJ, vectype, S}
	M = poPb.M
	N = div(length(u0) - 1, M)
	T = u0[end]
	h = T / M

	u0c = reshape(u0[1:end-1], N, M)
	duc = reshape(du[1:end-1], N, M)
	outc = similar(u0c)

	for ii=2:M
		outc[:, ii] .= (duc[:, ii] .- duc[:, ii-1]) .- h/2 .* (apply(poPb.J(u0c[:, ii]), duc[:, ii]) .+ apply(poPb.J(u0c[:, ii-1]), duc[:, ii-1]) )
	end

	# closure condition
	outc[:, 1] .= duc[:, M] .- duc[:, 1]

	δ = 1e-9
	dTFper = (poPb(vcat(u0[1:end-1], T + δ)) - poPb(u0)) / δ
	return vcat(vec(outc) .+ dTFper[1:end-1] .* du[end],
				dot(duc[:, 1], poPb.ϕ) + dTFper[end] * du[end])
end

"""
Sparse Matrix expression expression of the Jacobian for the periodic problem computed at the space-time guess: `u0`
"""
function JacobianPOTrap(poPb::PeriodicOrbitTrap{TF, TJ, vectype, S}, u0::vectype, γ = 1.0) where {TF, TJ, vectype, S}
	# extraction of various constants
	M = poPb.M
	N = div(length(u0) - 1, M)
	T = u0[end]
	h = T / M

	J = BlockArray(spzeros(M * N, M * N), N * ones(Int64,M),  N * ones(Int64,M))

	In = spdiagm( 0 => ones(N))
	On = spzeros(N, N)

	u0c = reshape(u0[1:end-1], N, M)
	outc = similar(u0c)

	for ii=2:M
		Jn = In - h/2 .* poPb.J(u0c[:, ii])
		setblock!(J, Jn, ii, ii)

		Jn = -In - h/2 .* poPb.J(u0c[:, ii-1])
		setblock!(J, Jn, ii,ii-1)
	end
	setblock!(J, -γ * In, 1, 1)
	setblock!(J,  In, 1, M)
	return J
end

"""
Function waiting to be accepted to BlockArrays.jl
"""
function blockToSparse(J::AbstractBlockArray)
	nl, nc = size(J.blocks)
	# form the first line of blocks
	res = J[Block(1,1)]
	for j=2:nc
		res = hcat(res, J[Block(1,j)])
	end
	# continue with the other lines
	for i=2:nl
		line = J[Block(i,1)]
		for j=2:nc
			line = hcat(line, J[Block(i,j)])
		end
		res = vcat(res,line)
	end
	return res
end

function (poPb::PeriodicOrbitTrap{TF, TJ, vectype, S})(u0::vectype, tp::Symbol = :jacsparse) where {TF, TJ, vectype, S}
	# extraction of various constants
	M = poPb.M
	N = div(length(u0) - 1, M)
	T = u0[end]
	h = T / M
	J_block = JacobianPOTrap(poPb, u0)

	# we now set up the last line / column
	δ = 1e-9
	dTFper = (poPb(vcat(u0[1:end-1], T + δ)) - poPb(u0)) / δ

	# this bad for performance. Get converted to SparseMatrix at the next line
	J = blockToSparse(J_block) # most of the compute time is here!!
	J = hcat(J, dTFper[1:end-1])
	J = vcat(J, spzeros(1, N*M + 1))

	J[N*M+1, 1:N] .=  poPb.ϕ
	J[N*M+1, N*M+1] = dTFper[end]
	return J
end

####################################################################################################
# Computation of Floquet Coefficients
# THIS IS WORK IN PROGRESS, DOES NOT WORK WELL YET
"""
Matrix-Free expression expression of the Monodromy matrix for the periodic problem computed at the space-time guess: `u0`
"""
# function FloquetPeriodicFD(poPb::PeriodicOrbitTrap{vectype, S}, u0::vectype, du::vectype) where {vectype, S}
# 	# extraction of various constants
# 	M = poPb.M
# 	N = div(length(u0)-1, M)
# 	T = u0[end]
# 	h = T / M
#
# 	out = copy(du)
#
# 	u0c = reshape(u0[1:end-1], N, M)
#
# 	for ii = 2:M
# 		out .= out./h .+ 1/2 .* apply(poPb.J(u0c[:, ii-1]), out)
# 		res, _ = poPb.linsolve(I/h - 1/2 * poPb.J(u0c[:, ii]), out)
# 		res .= out
# 	end
# 	return out
# end
#
# struct FloquetFD <: AbstractEigenSolver
# 	poPb
# end
#
# function (fl::FloquetFD)(J, sol, nev)
# 	# @show sol.p
# 	# @show length(sol.u)
# 	Jmono = x -> FloquetPeriodicFD(fl.poPb, sol, x)
# 	n = div(length(sol)-1, fl.poPb.M)
# 	@show n
# 	vals, vec, info = KrylovKit.eigsolve(Jmono,rand(n),15, :LM)
# 	return log.(vals), vec, true, info.numops
# end
