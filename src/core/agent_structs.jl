using Agents


mutable struct BlockGroup <: AbstractAgent
    #Attributes
    id::Int64
    pos::Dims{2}
    GEOID::Int64
    #geometry::String
    area::Float64
    #land_elevation
    init_pop::Int64
    perc_fld_area::Float64
    pop90::Int64
    mhi90::Int64 
    hhsize90::Float64 
    coastdist::Float64 
    cbddist::Float64 
    hhtrans93::Float64 
    salesprice93::Float64
    salespricesf93::Float64

    population::Int64
    flood_hazard::Float64
    new_price::Float64
    years_since_major_flooding::Int64
    occupied_units::Int64
    available_units::Int64
    pop_density::Float64
    
    demand_exceeds_supply::Vector{Bool}
    new_units_constructed::Int64
    avg_hh_size::Float64
    avg_home_price::Float64
    avg_hh_income::Float64    
end

 #row.geometry,
function add_bg(row, no_of_years)

    new_bg = BlockGroup(Int(row.fid_1),(0,0),
    row.GEOID,row.ALAND, 
    row.AJWME001, row.perc_fld_area,
    row.pop1990, row.mhi1990, row.hhsize1990,
    row.coastdist, row.cbddist, row.hhtrans1993,
    row.salesprice1993, row.salespricesf1993,
    0,0,row.new_price,0, 0,0,0.0,repeat([false], no_of_years),0,0.0,0.0,0.0)
    
    return new_bg
end

mutable struct HHAgent <: AbstractAgent
    #Attributes
    id::Int64
    pos::Dims{2}
    bg_id::Int64
    no_hhs_per_agent::Int64
    hh_size::Int64
    inc_cat::Int64 #Income Category: 1 => low, 2 => middle, 3 => high
    income::Float64 #Average income
    population::Int64
    #Track number oh households occupying each housing type
    occ_low::Int64
    occ_mid::Int64
    occ_high::Int64
    #Properties
    n_move::Int64
    n_stay::Int64
    simple_avoidance_perc::Float64
    #hh_utilities::Dict()
end




#Create Agent Struct to store unassigned/relocating agents 
mutable struct House <: AbstractAgent
    #Attributes
    id::Int64
    pos::Dims{2}
    bg_id::Int64
    quality::Int64 #Housing Category: 1 => low, 2 => middle, 3 => high
    occupied_units::Int64
    available_units::Int64
    capacity::Int64
    value::Float64
end