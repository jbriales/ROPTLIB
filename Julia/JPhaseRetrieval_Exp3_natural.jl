
# JTestPhaseRetrieval.jl
# Apply Riemannian method for Phase Retrieval problem
#
# --- by Wen Huang

#--------------------main test function-----------------------------------------
function JPhaseRetrieval_Exp3_natural()
	FFTW.set_num_threads(8)

	global phase = map(x->eval(parse(x)), readcsv("goldballs.txt"))

#	phasereal = readdlm("galaxy.txt", ',')
#	global phase = complex(phasereal, zeros(size(phasereal)))

	phase = phase / norm(phase)
	global n1 = size(phase, 1)
	global n2 = size(phase, 2)
	global n = n1 * n2
	global l = 20
	global m = l * n
	global p = 1
	global delta = 0.95
	global kappa = 1 / n
	global tol = 1e-16

	# problem related parameters
	global seed = 1#Int64(floor(rand() * 1000000))
	println("seed:", seed)
	srand(Int64(seed))
	global masks = complex(randn(n1, n2, l), randn(n1, n2, l))
#	global masks = octanaryrandom(n1, n2, l)
	vphase = reshape(phase, n, 1)
	global b = complex(zeros(m, 1),zeros(m, 1))
	for i in 1 : l
		zi = reshape(fft(phase .* masks[:, :, i]) / sqrt(n), n, 1)
		b[(i - 1) * n + 1 : i * n] = conj(zi) .* zi;
	end

	# initial iterate.
	# initial iterate for Riemannian approach.
	(initialX::Array{Complex{Float64}, 2}, inittime) = InitialIterate(p, 10, masks, n, l, m, b)
	println("dist(sol, xinit) / |sol|:", vecnorm(vphase - initialX * (initialX'*vphase) / norm(initialX'*vphase)) / vecnorm(phase))

	# set domain manifold to be the complex noncompact Stiefel manifold quotient the unitary group
	mani1 = "CpxNStQOrth"; ManArr = [pointer(mani1)]
	UseDefaultArr = [-1] # -1 means that the default value in C++ is used.
	numofmani = [1]
	# The size is n by p
	ns = [n]
	ps = [p]
	Mparams = ManiParams(0, length(ManArr), pointer(ManArr), pointer(numofmani), pointer(UseDefaultArr), pointer(UseDefaultArr), pointer(ns), pointer(ps))

	# set function handles
	fname = "func"
	gfname = "gfunc"
	hfname = "hfunc"
	isstopped = "stopfunc"
	LinesearchInput = "" # or "LSfunc" to use the function defined below
	Handles = FunHandles(pointer(fname), pointer(gfname), pointer(hfname), pointer(isstopped), pointer(LinesearchInput))

	# set solvers by modifying the default one.
	method = "LRBFGS"
	Sparams.name = pointer(method)
	Sparams.OutputGap = 10
	Sparams.LengthSY = 2
	Sparams.Min_Iteration = 10
	Sparams.Max_Iteration = 1000
	Sparams.DEBUG = 2
	Sparams.Tolerance = tol
	Sparams.Stop_Criterion = 2
	Sparams.Accuracy = 1e-6
	Sparams.Finalstepsize = 1
	Sparams.IsCheckGradHess = 0
	Sparams.IsCheckParams = 0
	Sparams.isconvex = 1
	#Sparams.Initstepsize = stepsize0

	# use locking condition or not
	HasHHR = 0::Int64
	FinalIterate = []; FF = []; GG = []; TT = []; time = 0; nf = 0; ng = 0; nR = 0; nH = 0; nV = 0; nVp = 0; nfft = 10 * 2 * l * p; nn = 0;
	while true
		global p
		println("rank is ", p)
		ps = [p]
		Mparams.p = pointer(ps)
		# Call the solver and get results. See the user manual for details about the outputs.
		(FinalIterate, fv, gfv, gfgf0, iter, nfi, ngi, nRi, nVi, nVpi, nHi, ComTime, funs, grads, times) = DriverJuliaOPT(Handles, Sparams, Mparams, HasHHR, initialX)

		if(length(TT) > 0)
			FF = [FF; funs]
			GG = [GG; grads]
			TT = [TT; times + TT[end]]
		else
			FF = funs
			GG = grads
			TT = times
		end
		time += ComTime; nf += nfi; ng += ngi; nR += nRi; nH += nHi; nV += nVi; nVp += nVpi; 
		nfft += (nfi + ngi) * l * p; nn += 2 * ngi * p^2 + 6 * p^2 * (iter) + ((p > 1) ? 2 * (iter - 1) * p^2 : 0);
		if(p == 1)
			println("dist(sol, xsol) / |sol|:", vecnorm(vphase - FinalIterate * (FinalIterate'*vphase) / norm(FinalIterate'*vphase)) / vecnorm(vphase))
			break;
		end
		(U, S) = svd(FinalIterate)
		normSdsqrk = norm(S) / sqrt(p)
		for i = 1 : p
			if(S[i] / normSdsqrk < delta)
				initialX = U[:, 1 : i - 1] * diagm(S[1 : i - 1])
				break;
			end
		end
		p = size(initialX, 2)
		if(p == 1)
			println("dist(sol, xinit by rank reduce) / |sol|:", vecnorm(vphase - initialX * (initialX'*vphase) / norm(initialX'*vphase)) / vecnorm(vphase))
		end
	end
	println("Num of total iter.:", length(FF), ", total time:", time + inittime, ", nf:", nf, ", ng:", ng, ", nH:", nH, ", nV:", nV, ", nR:", nR,
			", nfft:", nfft, ", nn:", nn)

	return FinalIterate
end

function octanaryrandom(n1, n2, l)
	masks = complex(zeros(n1, n2, l), zeros(n1, n2, l))
	for i in 1 : n1
		for j in 1 : n2
			for k in 1 : l
				tmp = rand()
				if(tmp < 0.25)
					b1 = 1
				elseif(tmp < 0.5)
					b1 = -1
				elseif(tmp < 0.75)
					b1 = -im
				else
					b1 = im
				end
				tmp = rand()
				if(tmp < 0.8)
					b2 = sqrt(2.0)/2
				else
					b2 = sqrt(3.0)
				end
				masks[i, j, k] = b1 * b2
			end
		end
	end
	return masks
end

function InitialIterate(k::Int64, niter::Int64, masks::Array{Complex{Float64}}, n::Int64, l::Int64, m::Int64, b::Array{Complex{Float64}})::Tuple{Array{Complex{Float64}}, Float64}
	srand(Int64(seed))
	tic()
	lambda = sqrt(sum(b) / real(sum(conj(masks) .* masks)) * n)
	initialX::Array{Complex{Float64}, 2} = complex(randn(n, k), randn(n, k))
	initialX = qr(complex(randn(n, k), randn(n, k)))[1]
	for i in 1 : niter
		println(i)
		initialX = qr(Ax(initialX, k, masks, n, l, m))[1]
	end
	time = toc()
	return (lambda * initialX, time)
end

function Ax(x::Array{Complex{Float64}}, k::Int64, masks::Array{Complex{Float64}}, n::Int64, l::Int64, m::Int64)::Array{Complex{Float64}}
	sqrtn::Float64 = sqrt(n)
	ZY::Array{Complex{Float64}, 2} = zeros(m, k)
	temp::Array{Complex{Float64}} = zeros(n, 1)
	for i in 1 : l
		for j in 1 : k
			temp[:] = reshape(fft(reshape(x[:, j], n1, n2) / sqrtn .* masks[:, :, i]), n, 1)
			ZY[(i - 1) * n + 1 : i * n, j] = temp
		end
	end
	DZY::Array{Complex{Float64}, 2} = zeros(m, k)
	for i in 1 : k
		DZY[:, i] = b .* ZY[:, i]
	end

	Y::Array{Complex{Float64}, 2} = zeros(n, k)
	tmp::Array{Complex{Float64}} = zeros(n, k)
	for i in 1 : l
		temp *= 0
		for j in 1 : k
			tmp[:, j] = reshape(ifft(reshape(DZY[(i - 1) * n + 1 : i * n, j] * sqrtn, n1, n2)), n, 1)
			tmp[:, j] = conj(reshape(masks[:, :, i], n, 1)) .* tmp[:, j]
		end
		Y += tmp
	end
	return Y
end

# Define function handles
# The function names are assigned to the "FunHandles" struct.
function func(xreal::Array{Float64}, inTmpreal::Array{Float64})
	x::Array{Complex{Float64}} = real2complex(xreal)
	x = reshape(x, n, p) # All the input argument is a vector. One has to reshape it to have a proper size
	sqrtn::Float64 = sqrt(n)
	outTmp::Array{Complex{Float64}, 2} = zeros(m, p + 1) # the first k columns are for ZY and the last column is for D.
	temp::Array{Complex{Float64}, 2} = zeros(n, 1)
	sZqi::Array{Complex{Float64}, 2} = zeros(n, 1)
	for i in 1 : l
		sZqi *= 0
		for j in 1 : p
			temp[:] = reshape(fft(reshape(x[:, j], n1, n2) / sqrtn .* masks[:, :, i]), n, 1)
			outTmp[(i - 1) * n + 1 : i * n, j] = temp
			sZqi += conj(temp) .* temp
		end
		outTmp[(i - 1) * n + 1 : i * n, p + 1] = sZqi[:] - b[(i - 1) * n + 1 : i * n]
	end
	output::Float64 = norm(outTmp[:, p + 1])^2 / norm(b)^2
	if(p != 1)
		output += kappa * vecnorm(x)^2
	end
	return (output, complex2real(outTmp)) # The temparary data "outTmp" will replace the "inTmp"
end

function gfunc(xreal::Array{Float64}, inTmpreal::Array{Float64}) # The inTmp is the temparary data computed in "func".
	x::Array{Complex{Float64}} = real2complex(xreal)
	inTmp::Array{Complex{Float64}} = real2complex(inTmpreal)
	x = reshape(x, n, p) # All the input argument is a vector. One has to reshape it to have a proper size
	inTmp = reshape(inTmp, m, p + 1) # All the input argument is a vector. One has to reshape it to have a proper size
	sqrtn::Float64 = sqrt(n)
	DZY::Array{Complex{Float64}, 2} = zeros(m, p)
	for i = 1 : p
		DZY[:, i] = inTmp[:, end] .* inTmp[:, i]
	end

	Y::Array{Complex{Float64}, 2} = zeros(n, p)
	temp::Array{Complex{Float64}, 2} = zeros(n, p)
	for i in 1 : l
		temp *= 0
		for j in 1 : p
			temp[:, j] = reshape(ifft(reshape(DZY[(i - 1) * n + 1 : i * n, j] * sqrtn, n1, n2)), n, 1)
			temp[:, j] = conj(reshape(masks[:, :, i], n, 1)) .* temp[:, j]
		end
		Y += temp
	end
	Y = 4.0 * Y / norm(b)^2
	if(p != 1)
		Y += kappa * 2 * x
	end
	gf::Array{Complex{Float64}} = Y / (x' * x)

	return (complex2real(gf), []) # If one does not want to change the temparary data, then let the outTmp be an empty array.
end

# action of the Hessian is not used. So use identity to avoid error.
function hfunc(xreal, inTmpreal, etareal)
	return (etareal, []) # If one does not want to change the temparary data, then let the outTmp be an empty array.
end

# Users can define their own stopping criterion by passing the name 
# of the function to the "isstopped" field in the object of structure FunHandles
function stopfunc(xreal, gfreal, fx, ngfx, ngfx0)
# x: the current iterate
# gf: the gradient at x
# gx: the function value at x
# ngfx: the norm of gradient at x
# ngfx0: the norm of gradient at the initial iterate
	x = real2complex(xreal)
	x = reshape(x, n, p)
	if(p > 1)
		S = svdvals(x)
		normSdsqrk = norm(S) / sqrt(p)
		for i = 1 : p
			if(S[i] / normSdsqrk < delta)
				return true
			end
		end
	end
	return (ngfx / ngfx0 < tol)
end
