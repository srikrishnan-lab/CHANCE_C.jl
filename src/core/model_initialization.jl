

#import Agent Types and Flood Dynamics Functions
include("agent_structs.jl")
include("flood_dynamics.jl")


mutable struct Properties{df<:DataFrame, scen<:String, itv<:String, t_p<:Int64, a_c<:Dict, r_s<:Dict, a_r<:Dict, b_d<:Dict,
     h_p<:Dict, u_hhs<:DataFrame, sy<:Int64, no_y<:Int64, f_mat<:Array, f_dict<:Dict, tick<:Int64}
    df::df
    total_population::t_p 
    agent_creation::a_c
    relo_sampler::r_s
    agent_relocate::a_r
    build_develop::b_d
    house_price::h_p
    hh_utilities_df::u_hhs
    no_of_years::no_y
    #Additional properties for Flood Dynamics
    flood_matrix::f_mat
    flood_dict::f_dict
    tick::tick
end

function Simulator(bg_df, pop_df, base_df, levee_df, model_evolve; slr_scen = "high", slr_rate = [3.03e-3,7.878e-3,2.3e-2],
    no_of_years = 10, no_hhs_per_agent=10, simple_avoidance_perc = 0.95, house_budget_mode = "rhea", hh_budget_perc = 0.33,
    hh_size = 2.7, pop_growth_mode = "perc" , pop_growth_perc = .01, 
    inc_growth_mode = "random_agent_replication", pop_growth_inc_perc = .90, inc_growth_perc = .05, 
    bld_growth_perc = .01, perc_move = 0.025, perc_move_mode = "random", house_choice_mode = "simple_avoidance_utility", 
    simple_anova_coefficients = [-121428, 294707, 130553, 128990, 154887], flood_coefficient = -500000, budget_reduction_perc = .90,
    stock_increase_mode = "simple_perc",  stock_increase_perc = .05,  housing_pricing_mode = "simple_perc", price_increase_perc = .05,
    levee = false, breach = true, breach_null = 0.45, risk_averse = 0.3, flood_mem = 10, fixed_effect = 0, seed = 1500,
)

    flood_rng = MersenneTwister(seed)
    f_matrix, f_dict = initialize_flood(flood_rng, base_df, levee_df; no_of_years = no_of_years, slr_scen = slr_scen, slr_rate = slr_rate, levee = levee, 
    breach = breach, breach_null = breach_null, gev_d = default_gev)

##Input Updating##
    #Replace missing hhsize values with median hhsize values
    med_hh = median(skipmissing(bg_df.hhsize1990))
    bg_df[!, "hhsize1990"] = coalesce.(bg_df.hhsize1990, med_hh)
    #Replace missing values in df with 0.0
    new_df = coalesce.(bg_df, 0.0)


    ##Create Keyword Arguments for step function parameters
    #AgentCreation
    agent_creation = Dict(:growth_mode => pop_growth_mode, :growth_rate => pop_growth_perc, :inc_growth_mode => inc_growth_mode, :pop_growth_inc_perc => pop_growth_inc_perc,
     :inc_growth_perc => inc_growth_perc, :no_hhs_per_agent => no_hhs_per_agent, :hh_size => hh_size, :simple_avoidance_perc => simple_avoidance_perc, :house_budget_mode => house_budget_mode,
     :hh_budget_perc => hh_budget_perc)

    #Agent relocation
    averse_move = Dict(:levee => levee, :risk_averse => risk_averse, :mem => flood_mem, :base_prob => perc_move, :f_e => fixed_effect)
    agent_relocate = Dict(:levee => levee, :f_e => fixed_effect, :house_choice_mode => house_choice_mode, :bg_sample_size => no_hhs_per_agent, :budget_reduction_perc => budget_reduction_perc,
     :a_c => simple_anova_coefficients, :f_c => flood_coefficient)

    #BuildingDevelopment
    build_develop = Dict(:stock_increase_mode => stock_increase_mode, :stock_increase_perc => stock_increase_perc)

    #HousingPricing
    house_price = Dict(:housing_pricing_mode => housing_pricing_mode, :price_increase_perc => price_increase_perc)

    #Set space for model 
    width = Int(ceil(sqrt(size(bg_df)[1])))
    space = GridSpace((width,width))

    parameters = Properties(new_df, 0, agent_creation, averse_move, agent_relocate, build_develop, house_price,
     DataFrame(hh_id = Int64[], bg_id = Int64[], bg_utility = Float64[]), no_of_years, f_matrix, f_dict, 0)

    model = ABM(
        Union{BlockGroup,HHAgent,Queue},
        space,
        scheduler = Schedulers.ByType((HHAgent, BlockGroup, Queue), false),
        model_step! = model_evolve,
        properties = parameters,
        rng = MersenneTwister(seed),
        warn = false,
    )

    #Create block group agents (network nodes)
    #AgentsIO.populate_from_csv!(model, filename, add_bg; row_number_is_id = true)
    for row in Tables.namedtupleiterator(model.df)
        add_agent_single!(add_bg(row, no_of_years), model)
    end
    
    #Create Household agents and add to block groups
    housing_df = DataFrame(name = Any[], no_hh_agents  = Any[], population = Int64[], average_income = Float64[], avg_hh_size = Float64[], 
    pop_density = Float64[], occupied_units = Int64[], available_units = Int64[], demand_exceeds_supply = Bool[])

    for bg in collect(allagents(model))
        dict, agent_df = agent_bin_cont(bg.GEOID, pop_df; no_hhs_per_agent=no_hhs_per_agent, group_col = group_col, cutoffs = cutoff_dict,
         house_budget_mode = house_budget_mode, hh_budget_perc = 0.33)

        for row in Tables.namedtupleiterator(agent_df)
            # indicate whether agent avoids flood zone (used in "simple avoidance utility" model)
            agent_avoid = rand(abmrng(model),Uniform(0,1)) <= simple_avoidance_perc ? true : false

            #Add agent to model
            add_agent!(bg.pos, HHAgent, model, bg.id, row.nrow, row.cat, row.race, Int(round(row.avg_hh_size)), 
            Float64(row.avg_income), house_budget_mode, model.tick, simple_avoidance_perc, agent_avoid, row.budget, hh_budget_perc)
        end
        #Calculate BG statistics based on agent properties within each BG
        #Future: Set income/size to NaN if avg == 0 (no agents in block group) 
        bg.avg_hh_income = dict[:avg_inc]
        bg.avg_hh_size = dict[:avg_hh_size]

        bg.population = dict[:total_pop]
        bg.pop_density = bg.population / bg.area
        #add occupied unit to associated block group node 
        bg.occupied_units = dict[:occupied]
        #Calculate available_units for associated block group 
        bg.available_units = dict[:vacant]
        
        #add to dataframe 
        push!(housing_df, [bg.id, no_of_hhs, bg.population, bg.avg_hh_income, bg.avg_hh_size, bg.pop_density, bg.occupied_units, bg.available_units, bg.demand_exceeds_supply[1]])
    end
    
    ##Create nodes to store relocating/unassigned agents
    #For relocating agents
    add_agent_single!(Relocating(0,(0,0)), model)
    #For unassigned agents (for new agent creation)
    add_agent_single!(Unassigned(-1,(0,0)), model)

    #model.avg_hh_income = mean([a.income for a in allagents(model) if a isa HHAgent])
    #model.avg_hh_size = mean([a.hh_size for a in allagents(model) if a isa HHAgent])
    model.total_population = sum([a.population for a in allagents(model) if a isa BlockGroup])

    # calculate normalized statistics for block groups
    housing_df[!,"average_income_norm"] = housing_df[!, "average_income"] / maximum(filter(!isnan,housing_df.average_income))

    # merge with housing_df with model.df to retain geometry features
    model.df = leftjoin(model.df, housing_df, on = "fid_1" => "name")

    return model
end









#FloodHazard 

#Zoning 

#Landscape Statistics


#function model_step!(model::ABM)
#reset queues and lists
    #model.unassigned_hhs = DataFrame()
    #model.relocating_hhs = DataFrame()
    #model.available_units_list - []
#end
