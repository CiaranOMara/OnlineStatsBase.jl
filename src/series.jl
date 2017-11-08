"""
    Series(stats...)
    Series(weight, stats...)
    Series(data, weight, stats...)
    Series(data, stats...)
    Series(weight, data, stats...)

Track any number of OnlineStats.

# Example 

    Series(Mean())
    Series(randn(100), Mean())
    Series(randn(100), Weight.Exponential(), Mean())
"""
mutable struct Series{N, T <: Tuple, W}
    stats::T
    weight::W
    n::Int
end
function Series(w::Weight.AbstractWeight, o::OnlineStat{N}...) where {N} 
    Series{N, typeof(o), typeof(w)}(o, w, 0)
end
Series(o::OnlineStat{N}...) where {N} = Series(default_weight(o), o...)

# init with data
Series(y::Data, o::OnlineStat{N}...) where {N} = (s = Series(o...); fit!(s, y))
function Series(y::Data, wt::Weight.AbstractWeight, o::OnlineStat{N}...) where {N}
    s = Series(wt, o...)
    fit!(s, y)
end
Series(wt::Weight.AbstractWeight, y::Data, o::OnlineStat{N}...) where {N} = Series(y, wt, o...)


#-----------------------------------------------------------------------# methods
function Base.show(io::IO, s::Series)
    header(io, name(s))
    print(io, "┣━━━━━━ "); println(io, "$(weight(s)), nobs = $(nobs(s))")
    print(io, "┗━━━┓")
    n = length(stats(s))
    i = 0
    for o in stats(s)
        i += 1
        char = ifelse(i == n, "┗━━", "┣━━")
        print(io, "\n    $char $(name(o)): $(value(o))")
    end
end

stats(s::Series) = s.stats
weight(s::Series) = s.weight
value(s::Series) = value.(stats(s))
nobs(s::Series) = s.n

#-----------------------------------------------------------------------# fit! 0
function fit!(s::Series{0}, y::ScalarOb)
    s.n += 1
    γ = s.weight(s.n)
    map(x -> fit!(x, y, γ), stats(s))
end
function fit!(s::Series{0}, y::ScalarOb, γ::Float64)
    s.n += 1
    map(x -> fit!(x, y, γ), stats(s))
end
function fit!(s::Series{0}, y::AbstractArray)
    for yi in y 
        fit!(s, yi)
    end
    s
end
function fit!(s::Series{0}, y::AbstractArray, γ::Float64)
    for yi in y 
        fit!(s, yi, γ)
    end
    s
end
function fit!(s::Series{0}, y::AbstractArray, γ::Vector{Float64})
    for (yi, γi) in zip(y, γ) 
        fit!(s, yi, γi)
    end
    s
end
#-----------------------------------------------------------------------# fit! 1 
function fit!(s::Series{1}, y::VectorOb)
    s.n += 1
    γ = s.weight(s.n)
    map(x -> fit!(x, y, γ), stats(s))
    s
end
function fit!(s::Series{1}, y::VectorOb, γ::Float64)
    s.n += 1
    map(x -> fit!(x, y, γ), stats(s))
    s
end
function fit!(s::Series{1}, y::AbstractMatrix, ::Rows = Rows())
    n, p = size(y)
    buffer = Vector{eltype(y)}(p)
    for i in 1:n
        for j in 1:p
            @inbounds buffer[j] = y[i, j]
        end
        fit!(s, buffer)
    end
    s
end
function fit!(s::Series{1}, y::AbstractMatrix, γ::Float64, ::Rows = Rows())
    n, p = size(y)
    buffer = Vector{eltype(y)}(p)
    for i in 1:n
        for j in 1:p
            @inbounds buffer[j] = y[i, j]
        end
        fit!(s, buffer, γ)
    end
    s
end
function fit!(s::Series{1}, y::AbstractMatrix, γ::Vector{Float64}, ::Rows = Rows())
    n, p = size(y)
    n == length(γ) || error("Weight vector has length $(length(γ)) instead of $n")
    buffer = Vector{eltype(y)}(p)
    for i in 1:n
        for j in 1:p
            @inbounds buffer[j] = y[i, j]
        end
        @inbounds fit!(s, buffer, γ[i])
    end
    s
end
function fit!(s::Series{1}, y::AbstractMatrix, ::Cols)
    p, n = size(y)
    buffer = Vector{eltype(y)}(p)
    for i in 1:n
        for j in 1:p
            @inbounds buffer[j] = y[j, i]
        end
        fit!(s, buffer)
    end
    s
end
function fit!(s::Series{1}, y::AbstractMatrix, γ::Float64, ::Cols)
    p, n = size(y)
    buffer = Vector{eltype(y)}(p)
    for i in 1:n
        for j in 1:p
            @inbounds buffer[j] = y[j, i]
        end
        fit!(s, buffer, γ)
    end
    s
end
function fit!(s::Series{1}, y::AbstractMatrix, γ::Vector{Float64}, ::Cols)
    p, n = size(y)
    n == length(γ) || error("Weight vector has length $(length(γ)) instead of $n")
    buffer = Vector{eltype(y)}(p)
    for i in 1:n
        for j in 1:p
            @inbounds buffer[j] = y[j, i]
        end
        @inbounds fit!(s, buffer, γ[i])
    end
    s
end

#-----------------------------------------------------------------------# merging
function Base.merge(s1::T, s2::T, w::Float64) where {T <: Series}
    merge!(copy(s1), s2, w)
end
function Base.merge(s1::T, s2::T, method::Symbol = :append) where {T <: Series}
    merge!(copy(s1), s2, method)
end
function Base.merge!(s1::T, s2::T, method::Symbol = :append) where {T <: Series}
    n2 = nobs(s2)
    n2 == 0 && return s1
    s1.n += n2
    if method == :append
        merge!.(s1.stats, s2.stats, s1.weight(n2))
    elseif method == :mean
        γ1 = s1.weight(s1.n)
        γ2 = s2.weight(s2.n)
        merge!.(s1.stats, s2.stats, .5 * (γ1 + γ2))
    elseif method == :singleton
        merge!.(s1.stats, s2.stats, s1.weight(s1.n))
    else
        throw(ArgumentError("method must be :append, :mean, or :singleton"))
    end
    s1
end
function Base.merge!(s1::T, s2::T, w::Float64) where {T <: Series}
    n2 = nobs(s2)
    n2 == 0 && return s1
    0 <= w <= 1 || throw(ArgumentError("weight must be between 0 and 1"))
    s1.n += n2
    merge!.(s1.stats, s2.stats, w)
    s1
end
