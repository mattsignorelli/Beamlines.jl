const Q = 1.602176634e-19 # C
const C_LIGHT = 2.99792458e8 # m/s
const M_ELECTRON = 0.51099895069 # eV/c^2
const M_PROTON = 9.3827208943e8 # eV/c^2

struct Species
  name::String
  mass::Float64   # in eV/c^2
  charge::Float64 # in Coulomb
end

const ELECTRON = Species("electron", M_ELECTRON,-Q)
const POSITRON = Species("positron", M_ELECTRON,Q)

const PROTON = Species("proton", M_PROTON,Q)
const ANTIPROTON = Species("antiproton", M_PROTON,-Q)

calc_Brho(species::Species, E_ref) = @FastGTPSA E_ref/C_LIGHT*sqrt(1-(species.mass/E_ref)^2)
calc_E_ref(species::Species, Brho_ref) = @FastGTPSA sqrt((Brho_ref*C_LIGHT)^2 + species.mass^2)