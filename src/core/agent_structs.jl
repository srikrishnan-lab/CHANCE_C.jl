using Agents

@agent struct HHAgent(GridAgent{2})
    #Attributes
    bg_id::Int64
    no_hhs_per_agent::Int64
    group::Int64 #What population category they belong to
    occ_cat::Int64 #What housing category they live in
    race::Float64
    hh_size::Int64
    income::Float64
    utility::Dict{Int64,Float64} #bg.id (model id) => utility
    #Properties
    house_budget_mode::String
    year_of_residence::Int64
    simple_avoidance_perc::Float64
    flood_hazard::Vector{Float64}
    flood_experience::Float64
    avoidance::Bool
    house_budget::Float64
    hh_budget_perc::Float64
end


@agent struct BlockGroup(GridAgent{2})
    #Attributes
    GEOID::Int64
    area::Float64
    init_pop::Int64
    perc_fld_area::Float64
    init_mhi::Int64 
    init_hh_size::Float64 
    coastdist::Float64 
    cbddist::Float64  

    population::Int64
    flood_hazard::Float64
    base_utility::Union{Float64, Dict{Int64, Float64}}
    current_utility::Union{Float64, Dict{Int64, Float64}}
    new_price::Union{Float64, Dict{Int64, Float64}}
    years_since_major_flooding::Int64
    occupied_units::Union{Int64, Dict{Int64, Int64}}
    available_units::Union{Int64, Dict{Int64, Int64}}
    pop_density::Float64
    demand_exceeds_supply::Union{Vector{Float64}, Dict{Int64, Vector{Float64}}}
    new_units_constructed::Union{Int64, Dict{Int64, Int64}}
    avg_hh_size::Float64
    avg_home_price::Float64
    avg_hh_income::Float64    
end


#Create Agent Struct to store unassigned/relocating agents 
@agent struct Queue(GridAgent{2})
    #Attributes
    type::Symbol
end

Relocating(id, pos) = Queue(id, pos, :relocating)
Unassigned(id, pos) = Queue(id, pos, :unassigned)