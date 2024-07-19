### Integrate spatial flood inundation data from external hazard models, such as FastFlood

include(joinpath(dirname(dirname(@__DIR__)),"data/GEV_functions.jl"))

#levee breaching probability calculation
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

##Convert meters to feet 
m_to_ft(a::Float64) = a * 3.28084


##Determine whether breach occurs for given flood event
function breach_occur(f_depth; null = 0.45, rng = model.rng)
    #calculate breach probability
    prob_fail = levee_breach(f_depth; n_null = null)
    #Determine if Levee Breaches
    breach_outcome = rand(rng, Binomial(1,prob_fail))
    return breach_outcome
end

#Function from stack overflow: https://stackoverflow.com/questions/74852494/finding-the-closest-value-in-an-array-of-floats-efficiently
function find_closest(A::AbstractArray{T}, b::T; order::Bool) where {T<:Real}
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

function initialize_flood(model_rng, base_df, levee_df; no_of_years = 10, slr_scen = "high", slr_rate = [3.03e-3,7.878e-3,2.3e-2], levee = false, 
    breach = false, breach_null = 0.45, gev_d = default_gev)

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
    flood_record = [GEV_event(model_rng, d = gev_d) for _ in 1:no_of_years]
    #add SLR values to flood_events 
    slr_dict = Dict(["low", "medium","high"] .=> slr_rate)
    slr_record = slr_dict[slr_scen] .* collect(1:no_of_years)
    flood_record .+= slr_record
    
    
    #Determine which scenario to draw from (baseline or levee)
    if levee
        scen_record = Int.(ones(no_of_years) .+ 1)
        if breach
            flood_rec_ft = m_to_ft.(flood_record)
            breach_record = breach_occur.(flood_rec_ft; null = breach_null, rng = model_rng)
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

"""
#Read in flood area extent files
balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-housing-data/model_inputs/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-housing-data/model_inputs/surge_area_baltimore_levee.csv")))

#try initialize_flood
rng = MersenneTwister(1500)
f_matrix, f_dict = initialize_flood(rng, balt_base, balt_levee)
#Sort on fid_1 column. Extract only flood area values
sort!(balt_base, :fid_1)
base_extent = select(balt_base, Not([:Column1, :GISJOIN, :fid_1, :area]))

base_mat = Matrix(base_extent)

sort!(balt_levee, :fid_1)
levee_extent = select(balt_levee, Not([:Column1, :GISJOIN, :fid_1, :area]))
levee_mat = Matrix(levee_extent)
## Create Matrix 
x_dim, y_dim = size(base_mat)
flood_mat = reshape(reduce(hcat,[base_mat, levee_mat]), x_dim, y_dim,:)

## test
base_mat == flood_mat[:,:,1]
levee_mat == flood_mat[:,:,2]

rng = MersenneTwister(1500)
surge_range = parse.(Float64, names(base_extent))
flood_record = [GEV_event(rng; d = default_gev) for _ in 1:10]
push!(flood_record, 3.5)
#breach
flood_rec_ft = m_to_ft.(flood_record)
breach_record = breach_occur.(flood_rec_ft; null = 0.45, rng = rng)

find_closest.(Ref(surge_range), flood_record; order = false)
"""