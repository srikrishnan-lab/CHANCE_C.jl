include(joinpath(dirname(dirname(@__DIR__)),"data/GEV_functions.jl"))

"""
    levee_breach(flood_height; n_null=0.45)

Computes the probability of levee failure for a flood event
using a piecewise reliability model.

Failure probability is determined from:
- flood height
- levee fragility parameters
- uncertainty bounds on levee resistance

The function returns a probability between 0 and 1 representing
the likelihood of levee breach during the event.

# Arguments
- `flood_height`: Flood water height relative to levee elevation

# Keywords
- `n_null=0.45`: Reference levee fragility parameter

# Returns
- Probability of levee failure.
"""
function levee_breach(flood_height; n_null = 0.45)
    C = 0.237
    η = flood_height
    L = 30
    n_min = 0.25
    n_max = 0.55
    n_0 = n_null

    p_0 = 2*(n_max - n_min)^-1

    G_min = C *((1-n_max)/n_max) - (η/L)
    G_0 = C *((1-n_0)/n_0) - (η/L)
    G_max = C *((1-n_min)/n_min) - (η/L)

    if G_min > 0
        pf = 0
    elseif G_min <= 0 <= G_0
        t1 = 1 + (n_0/(n_max - n_0))
        t2 = (1/(G_min + (η/L) + C)) - (1/((η/L) + C))
        t3 = (p_0 * C^2)/(2*(n_max - n_0))
        t4 = (1/(G_min + (η/L) + C)^2) - (1/((η/L) + C)^2)

        pf = (p_0 * C * t1 * t2) - (t3 * t4)

    elseif G_0 < 0 <= G_max
        t1 = n_min/(n_0 - n_min)
        t2 = (1/((η/L) + C)) - (1/(G_0 + (η/L) + C))
        t3 = (p_0 * C^2)/(2*(n_0 - n_min))
        t4 = (1/((η/L) + C)^2) - (1/(G_0 + (η/L) + C)^2)

        p_G0 = p_0 * C *(1 + (n_0/(n_max - n_0))) * ((1/(G_min + (η/L) + C)) - (1/(G_0 + (η/L) + C))) - ((p_0 * C^2)/(2*(n_max - n_0))) * ((1/(G_min + (η/L) + C)^2) - (1/(G_0 + (η/L) + C)^2))

        pf = p_G0 + (p_0 * C * t1 * t2) - (t3 * t4)
    else
        pf = 1
    end
    return pf
end

"""
    m_to_ft(a::Float64)

Converts a value from meters to feet.

# Arguments
- `a::Float64`: Value in meters

# Returns
- Equivalent value in feet.
"""
m_to_ft(a::Float64) = a * 3.28084


"""
    breach_occur(f_depth; null=0.45, rng=model.rng)

Determines whether a levee breach occurs during a flood event.

Levee breach occurrence is sampled probabilistically using
the breach probability computed by `levee_breach`.

# Arguments
- `f_depth`: Flood depth or surge height

# Keywords
- `null=0.45`: Reference levee fragility parameter
- `rng=model.rng`: Random number generator used for sampling

# Returns
- `0` if no breach occurs
- `1` if levee breach occurs.
"""
function breach_occur(f_depth; null = 0.45, rng = model.rng)
    #calculate breach probability
    prob_fail = levee_breach(f_depth; n_null = null)
    #Determine if Levee Breaches
    breach_outcome = rand(rng, Binomial(1,prob_fail))
    return breach_outcome
end

"""
    find_closest(A::AbstractArray{T}, b::T; order::Bool)

Finds the index of the value in a sorted array closest to a target value.

Uses binary-search logic for efficient lookup within sorted arrays.

# Arguments
- `A`: Sorted array of numeric values
- `b`: Target value

# Keywords
- `order::Bool`: Whether the array is sorted in reverse order

# Returns
- Index of the closest value in `A`.
"""
function find_closest(A::AbstractArray{T}, b::T; order::Bool) where {T<:Real}
    #Function from stack overflow: https://stackoverflow.com/questions/74852494/finding-the-closest-value-in-an-array-of-floats-efficiently

    if length(A) <= 1
        return firstindex(A)
    end

    i = searchsortedfirst(A, b; rev = order)

    
    if i == firstindex(A)
        return i
    elseif i > lastindex(A)
        return lastindex(A)
    else
        prev_dist = b - A[i-1]
        next_dist = A[i] - b

        if abs(prev_dist) < abs(next_dist)
            return i - 1
        else
            return i
        end
    end
end


### Function wrapper for flood property initialization ###
## SLR Scenarios from NOAA for Baltimore:
    #high scenario of SL change projection for 2031 is 0.28m and 2.57m for 2130 (NOAA)
    #medium scenario of SL change projection for 2031 is 0.15m and 0.93m for 2130 (NOAA)
    #low scenario of SL change projection for 2031 is 0.11m and 0.41m for 2130 (NOAA)

"""
    initialize_flood(seed, base_df, levee_df;
                     no_of_years=10,
                     slr_scen="high",
                     slr_rate=[3.03e-3,7.878e-3,2.3e-2],
                     levee=false,
                     breach=false,
                     breach_null=0.45,
                     gev_d=default_gev)

Initializes stochastic flood hazard scenarios for the simulation.

The function:
- constructs flood inundation matrices from baseline and levee datasets
- simulates flood events using a generalized extreme value (GEV) distribution
- incorporates sea-level rise projections
- optionally models levee breach events
- maps simulated flood heights to nearest available surge datasets

Flood scenarios are returned as indexed records for each model year.

# Arguments
- `seed`: Random seed used for flood-event generation
- `base_df`: Baseline flood inundation dataset
- `levee_df`: Levee-protected flood inundation dataset

# Keywords
- `no_of_years=10`: Number of simulated years
- `slr_scen="high"`: Sea-level rise scenario
- `slr_rate=[...]`: Annual sea-level rise rates
- `levee=false`: Whether levee protection is enabled
- `breach=false`: Whether levee breach is modeled
- `breach_null=0.45`: Reference levee fragility parameter
- `gev_d=default_gev`: GEV distribution used for flood simulation

# Returns
- `flood_mat`: 3D array of flood inundation extents
- `rec_dict`: Dictionary mapping years to flood scenarios.
"""
    function initialize_flood(seed, base_df, levee_df; no_of_years = 10, slr_scen = "high", slr_rate = [3.03e-3,7.878e-3,2.3e-2], levee = false, 
    breach = false, breach_null = 0.45, gev_d = default_gev)

    flood_rng = MersenneTwister(seed)

## Create Matrix of surge from base and levee scenario ##
    #Sort on fid_1 column. Extract only flood area values
    sort!(base_df, :fid_1)
    base_extent = select(base_df, Not([:Column1, :GISJOIN, :GEOID, :fid_1, :area]))
    base_mat = Matrix(base_extent)

    sort!(levee_df, :fid_1)
    levee_extent = select(levee_df, Not([:Column1, :GISJOIN, :GEOID, :fid_1, :area]))
    levee_mat = Matrix(levee_extent)

    #Combine to create matrix
    x_dim, y_dim = size(base_mat)
    flood_mat = reshape(reduce(hcat,[base_mat, levee_mat]), x_dim, y_dim,:)

    ## Create record of flood return periods and breach events ##
    #Create GEV distribution
    flood_record = [GEV_event(flood_rng, d = gev_d) for _ in 1:no_of_years]
    #add SLR values to flood_events 
    slr_dict = Dict(["low", "medium","high"] .=> slr_rate)
    slr_record = slr_dict[slr_scen] .* collect(1:no_of_years)
    flood_record .+= slr_record
    
    
    #Determine which scenario to draw from (baseline or levee)
    if levee
        scen_record = Int.(ones(no_of_years) .+ 1)
        if breach
            flood_rec_ft = m_to_ft.(flood_record)
            breach_record = breach_occur.(flood_rec_ft; null = breach_null, rng = flood_rng)
            scen_record .-= breach_record
        end
    else
        scen_record = Int.(ones(no_of_years))
    end

    # match surge events from flood record with index of closest FastFlood event 
    surge_range = parse.(Float64, names(base_extent)) #get surge levels from input dataframe
    surge_index = find_closest.(Ref(surge_range), flood_record; order = false)

    #create dictionary of levee scenario and surge level indices for each model year
    rec_dict = Dict(collect(1:no_of_years) .=> zip(scen_record, surge_index))

    return flood_mat, rec_dict
end

####Flood initialization for hindcast
## Use when historical floods events are used
## Input should be formatted as Dataframe with Rows representing BlockGroups and Columns representing Years 
    #(With first column being the BG GEOID column). 

"""
    flood_history(base_df;
                  no_of_years=10,
                  start_year=1981,
                  slr_scen="high",
                  slr_rate=[3.03e-3,7.878e-3,2.3e-2],
                  standardization="normal")

Initializes flood hazard scenarios using historical flood records.

Historical flood data are converted into hazard matrices and optionally
normalized using z-score or min-max standardization.

This function is used for hindcast or historical flood simulations.

# Arguments
- `base_df`: Historical flood dataset indexed by BlockGroup and year

# Keywords
- `no_of_years=10`: Number of years included
- `start_year=1981`: Initial historical year
- `slr_scen="high"`: Sea-level rise scenario
- `slr_rate=[...]`: Sea-level rise rates
- `standardization="normal"`: Hazard normalization method

# Returns
- `flood_array`: ComponentArray containing raw and normalized flood hazards
- `rec_dict`: Dictionary mapping simulation years to flood records.
"""
function flood_history(base_df; no_of_years = 10, start_year = 1981, slr_scen = "high", slr_rate = [3.03e-3,7.878e-3,2.3e-2], standardization = "normal")
    #Sort df on GEOID
    sort!(base_df, :GEOID)
    #Select years of interest. Subset df
    flood_df = select(base_df,Symbol.(collect(range(start_year, start_year+(no_of_years-1), step = 1))))
    #Convert df to matrix
    flood_mat = zeros(size(flood_df)[1], size(flood_df)[2], 1)
    flood_mat_norm = copy(flood_mat) #For normalized hazard values
    flood_mat[:,:,1] = Matrix(flood_df)
    #Normalize flood extents
    if standardization == "normal"
        if std(flood_mat[:,:,1]) != 0
            flood_mat_norm[:,:,1] = (flood_mat[:,:,1] .- mean(flood_mat[:,:,1])) ./ std(flood_mat[:,:,1])
        end
    elseif standardization == "min-max"
        flood_mat_norm[:,:,1] = (flood_mat[:,:,1] .- minimum(flood_mat[:,:,1])) ./ (maximum(flood_mat[:,:,1]) .- minimum(flood_mat[:,:,1]))
    end
    #Create component array
    flood_array = ComponentArray(hazard=flood_mat, norm = flood_mat_norm)

    scen_record = Int.(ones(no_of_years))
    #create dictionary of flood scenario and model year for each model year
    #(This looks redundant, but done to keep the same formatting and indexing logic
    #  as the initialize_flood function)
    rec_dict = Dict(collect(1:no_of_years) .=> zip(scen_record, collect(1:no_of_years)))

    return flood_array, rec_dict
end




#Read in flood area extent files
#balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-housing-data/model_inputs/surge_area_baltimore_base.csv")))
#balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-housing-data/model_inputs/surge_area_baltimore_levee.csv")))

#try initialize_flood
#rng = MersenneTwister(1500)
#f_matrix, f_dict = initialize_flood(rng, balt_base, balt_levee)
#Sort on fid_1 column. Extract only flood area values
#sort!(balt_base, :fid_1)
#base_extent = select(balt_base, Not([:Column1, :GISJOIN, :fid_1, :area]))

#base_mat = Matrix(base_extent)

#sort!(balt_levee, :fid_1)
#levee_extent = select(balt_levee, Not([:Column1, :GISJOIN, :fid_1, :area]))
#levee_mat = Matrix(levee_extent)
## Create Matrix 
#x_dim, y_dim = size(base_mat)
#flood_mat = reshape(reduce(hcat,[base_mat, levee_mat]), x_dim, y_dim,:)

## test
#base_mat == flood_mat[:,:,1]
#levee_mat == flood_mat[:,:,2]

#rng = MersenneTwister(1500)
#surge_range = parse.(Float64, names(base_extent))
#flood_record = [GEV_event(rng; d = default_gev) for _ in 1:10]
#push!(flood_record, 3.5)
#breach
#flood_rec_ft = m_to_ft.(flood_record)
#breach_record = breach_occur.(flood_rec_ft; null = 0.45, rng = rng)

#find_closest.(Ref(surge_range), flood_record; order = false)