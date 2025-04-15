@kwdef mutable struct BendParams{T<:Number} <: AbstractParams
  g::T      = Float32(0.0) # Coordinate system curvature
  e1::T     = Float32(0.0) # Edge 1 angle as SBend from g_ref (e.g. e1 = 0.0 for SBend)
  e2::T     = Float32(0.0) # Edge 2 angle as SBend from g_ref (e.g. e2 = 0.0 for SBend)
  function BendParams(g, e1, e2)
    return new{promote_type(typeof(g),typeof(e1),typeof(e2))}(g, e1, e2)
  end
end

Base.eltype(::BendParams{T}) where {T} = T
Base.eltype(::Type{BendParams{T}}) where {T} = T

Base.:(==)(a::BendParams, b::BendParams) = a.g ≈ b.g && a.e1 ≈ b.e1 && a.e2 ≈ b.e2

# Note that here the reference energy is really needed to compute anything
# other than the above so there is no more work to do here. Must define 
# virtual properties for the rest of them.
