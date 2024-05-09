### Create GEV from Baltimore Tide data
#Load Tidal Data
dat_annmax = DataFrame(CSV.File(joinpath(@__DIR__,"balt_tide.csv")))
#Find Parameters
fm = gevfit(dat_annmax, :residual)
 
μ = location(fm)[1]
σ = Extremes.scale(fm)[1]
ξ = shape(fm)[1]

#Create GEV distribution
default_gev = GeneralizedExtremeValue(μ, σ, ξ)


###Define function to calculate return level
#rp is the return period expressed as fraction (ex. 1/100 = 100 -yr event)
function GEV_return(rp,mu = μ, sig = σ, xi = ξ)
    y_p = -log(1 - rp)
    z_p = mu - ((sig/xi)*(1 - y_p^(-xi)))
    return z_p
end

#Define Function to calculate return period from return level
function GEV_rp(z_p, mu = μ, sig = σ, xi = ξ)
    y_p = 1 + (xi * ((z_p - mu)/sig))
    rp = -exp(-y_p^(-1/xi)) + 1
    rp = round(rp, digits = 3)
    return 1/rp
end

#Create GEV distribution from parameters
function GEV_event(rng; d = default_gev) #input GEV distribution 
    flood_depth = rand(rng, d)
    return flood_depth
end

"""
#Create flood record to read into model
gev_rng = MersenneTwister(1897)
flood_record = [GEV_event(gev_rng) for _ in 1:10]

scen_record = Int.(ones(10) .+ 1)
breach_record = breach_occur.(flood_record; null = 0.45, rng = gev_rng)

scen_record .-= breach_record

#get return periods from corresponding flood events
flood_rp = 1 ./ GEV_rp.(flood_record)
rp_ind = find_closest.(Ref(rp_record), flood_rp; order = true)


#create dictionary of return periods and breach occurrence
rec_dict = Dict(collect(1:10) .=> zip(scen_record,rp_ind))

time_interval = range(10, 1, step = -1)

flood_mem = get.(Ref(rec_dict),collect(time_interval), Ref((0,0)))
[breach + rp for (breach,rp) in flood_mem]

collect(time_interval)[Bool.(rand(gev_rng, Binomial(1,0.5), 10))]


## Flood memory updating ##

count(!iszero,[flood_matrix[2, rp, breach] for (breach,rp) in flood_mem])
"""