
abstract type AbstractParams end

# By making the key the AbstractParams type name, we always have a consistent internal definition
const ParamDict = Dict{Type{<:AbstractParams}, AbstractParams}
Base.setindex!(h::ParamDict, v, key) = error("Incorrect key/value types for ParamDict")

function Base.setindex!(h::ParamDict, v::AbstractParams, key::Type{<:AbstractParams})
  # 208 ns and 3 allocations to check that we set correctly
  # Parameter groups rarely added so perfectly fine
  typeof(v) <: key || error("Key type $key does not match parameter group type $(typeof(v))")
  # The following is copy-pasted directly from Base dict.jl ==========
  index, sh = Base.ht_keyindex2_shorthash!(h, key)

  if index > 0
      h.age += 1
      @inbounds h.keys[index] = key
      @inbounds h.vals[index] = v
  else
      @inbounds Base._setindex!(h, v, key, -index, sh)
  end

  return h
  # ==================================================================
end

# Equality of ParamDict does NOT consider BeamlineParams
# following is copied from Base abstractdict.jl with modification
# to ignore BeamlineParams if present
function Base.:(==)(l::ParamDict, r::ParamDict)
  L_l = length(l) - (haskey(l, BeamlineParams) ? 1 : 0)
  L_r = length(r) - (haskey(r, BeamlineParams) ? 1 : 0)
  L_l != L_r && return false
  anymissing = false
  for pair in l
      if pair[1] == BeamlineParams
        continue
      end
      isin = in(pair, r)
      if ismissing(isin)
          anymissing = true
      elseif !isin
          return false
      end
  end
  return anymissing ? missing : true
end

@kwdef struct LineElement
  pdict::ParamDict = ParamDict(UniversalParams => UniversalParams())
end

Base.:(==)(a::LineElement, b::LineElement) = a.pdict == b.pdict

function LineElement(class::String; kwargs...)
  ele = LineElement()
  ele.class = class
  for (k, v) in kwargs
    setproperty!(ele, k, v)
  end
  return ele
end

# Common class choices
Solenoid(; kwargs...)   = LineElement("Solenoid"; kwargs...)
Quadrupole(; kwargs...) = LineElement("Quadrupole"; kwargs...)
Sextupole(; kwargs...)  = LineElement("Sextupole"; kwargs...)
Drift(; kwargs...)      = LineElement("Drift"; kwargs...)
Octupole(; kwargs...)   = LineElement("Octupole"; kwargs...)
Multipole(; kwargs...)  = LineElement("Multipole"; kwargs...)
Marker(; kwargs...)     = LineElement("Marker"; kwargs...)

# The bend is special:
function SBend(; kwargs...)
  if :K0 in keys(kwargs) && !(:g in keys(kwargs))
    return LineElement("SBend"; g=kwargs[:K0], kwargs...)
  elseif !(:K0 in keys(kwargs)) && (:g in keys(kwargs))
    return LineElement("SBend"; K0=kwargs[:g], kwargs...)
  else
    return LineElement("SBend"; kwargs...)
  end
end

@kwdef mutable struct UniversalParams <: AbstractParams
  tracking_method = SciBmadStandard()
  L::Number       = 0.0
  class::String   = ""
  name::String    = ""
end

function Base.:(==)(a::UniversalParams, b::UniversalParams)
  return a.tracking_method == b.tracking_method &&
         a.L               == b.L
         # Only compare things that affect the physics
         #a.class           == b.class &&
         #a.name            
end

# Use Accessors here for default bc super convenient for replacing entire (even mutable) type
# For more complex params (e.g. BMultipoleParams) we will need custom override
replace(p::AbstractParams, key::Symbol, value) = set(p, opcompose(PropertyLens(key)), value)

function Base.getproperty(ele::LineElement, key::Symbol)
  if key == :pdict 
    return getfield(ele, :pdict)
  elseif haskey(PARAMS_MAP, key) # To get parameters struct
    if haskey(ele.pdict, PARAMS_MAP[key])
      return getindex(ele.pdict, PARAMS_MAP[key])
    else
      return nothing
    end
  elseif haskey(VIRTUAL_GETTER_MAP, key) # Virtual properties override regular properties
      return VIRTUAL_GETTER_MAP[key](ele, key)
  elseif haskey(PROPERTIES_MAP, key)  # To get a property in a parameter struct
    return getproperty(getindex(ele.pdict, PROPERTIES_MAP[key]), key)
  else
    if haskey(VIRTUAL_SETTER_MAP, key)
      error("LineElement property $key is write-only")
    else
      error("Type LineElement has no property $key")
    end
  end
end

function Base.setproperty!(ele::LineElement, key::Symbol, value)
  if haskey(PARAMS_MAP, key) # Setting whole parameter struct
    setindex!(ele.pdict, value, PARAMS_MAP[key])
  elseif haskey(VIRTUAL_SETTER_MAP, key) # Virtual properties override regular properties
    return VIRTUAL_SETTER_MAP[key](ele, key, value)
  elseif haskey(PROPERTIES_MAP, key)
    if !haskey(ele.pdict, PROPERTIES_MAP[key])
      # If the parameter struct associated with this symbol does not exist, create it
      # This could be optimized in the future with a `place` function
      # That is similar to `replace` but just has the type
      # Though adding fields is not done very often so is fine
      setindex!(ele.pdict, PROPERTIES_MAP[key](), PROPERTIES_MAP[key])
    end
    p = getindex(ele.pdict, PROPERTIES_MAP[key])
    # Function barrier for speed
    @noinline _setproperty!(ele.pdict, p, key, value)
  else
    if haskey(VIRTUAL_GETTER_MAP, key)
      error("LineElement property $key is read-only")
    else
      error("Type LineElement has no property $key")
    end
  end
end

function _setproperty!(pdict::ParamDict, p::AbstractParams, key::Symbol, value)
  if hasproperty(p, key) # Check if we can put this value in current struct
    T = typeof(getproperty(p, key))
    if promote_type(typeof(value), T) == T
      return setproperty!(p, key, value)
    end
  end
  return pdict[PROPERTIES_MAP[key]] = replace(p, key, value)
end

function deepcopy_no_beamline(ele::LineElement)
  newele = LineElement(ele.class)
  for (key, p) in ele.pdict
    if key != BeamlineParams
      setindex!(newele.pdict, deepcopy(p), key)
    end
  end
  return newele
end

#Base.fieldnames(::Type{LineElement}) = tuple(:pdict, keys(PROPERTIES_MAP)..., keys(PARAMS_MAP)...)
#Base.fieldnames(::LineElement) = tuple(:pdict, keys(PROPERTIES_MAP)..., keys(PARAMS_MAP)...)
#Base.propertynames(::Type{LineElement}) = tuple(:pdict, keys(PROPERTIES_MAP)..., keys(PARAMS_MAP)...)
function Base.propertynames(::LineElement)
  virt = union(keys(VIRTUAL_GETTER_MAP),keys(VIRTUAL_SETTER_MAP))
  prop = keys(PROPERTIES_MAP)
  param = keys(PARAMS_MAP)
  syms = [:pdict, Symbol.(param)..., virt..., prop...]
  return syms
end
