using Agents

@agent struct HHAgent(GridAgent{2})
    #Attributes
    bg_id::Int64
    no_hhs_per_agent::Int64
    group::String
    race::Float64
    hh_size::Int64
    income::Float64
    #Properties
    house_budget_mode::String
    year_of_residence::Int64
    simple_avoidance_perc::Float64
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

function add_bg(row, no_of_years)

    new_bg = BlockGroup(Int(row.fid_1),(0,0),row.GEOID, row.ALAND, 
    row.AJWME001, 0, row.pop1990, row.mhi1990, row.hhsize1990,
    row.coastdist, row.cbddist, row.hhtrans1993,
    row.salesprice1993, row.salespricesf1993,
    0,0,"no",row.new_price,0, 0,0,0.0,"no",repeat([false], no_of_years),0,0.0,0.0,0.0)
    
    return new_bg
end

#Create Agent Struct to store unassigned/relocating agents 
@agent struct Queue(GridAgent{2})
    #Attributes
    type::Symbol
end

Relocating(id, pos) = Queue(id, pos, :relocating)
Unassigned(id, pos) = Queue(id, pos, :unassigned)