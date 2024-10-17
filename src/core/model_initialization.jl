

#import Agent Types and Flood Dynamics Functions
include("agent_structs.jl")
include("flood_dynamics.jl")


mutable struct Properties{df<:DataFrame, t_p<:Int64, a_c<:Dict, r_s<:Dict, a_r<:Dict, b_d<:Dict,
     h_p<:Dict, u_hhs<:Array, p_t<:Array, no_y<:Int64, f_mat<:Array, f_dict<:Dict, tick<:Int64}
    df::df
    total_population::t_p 
    agent_creation::a_c
    relo_sampler::r_s
    agent_relocate::a_r
    build_develop::b_d
    house_price::h_p
    hh_utilities::u_hhs
    pop_transfers::p_t
    #Additional properties for Flood Dynamics
    flood_matrix::f_mat
    flood_dict::f_dict
    no_of_years::no_y
    tick::tick
end

function Simulator(bg_df, base_df, levee_df, model_evolve; slr_scen = "high", slr_rate = [3.03e-3,7.878e-3,2.3e-2], initial_vacancy = 0.20, no_of_years = 10, 
    no_hhs_per_agent=10, simple_avoidance_perc = 0.95, house_budget_mode = "rhea", hh_budget_perc = 0.33,
    hh_size = 2.7, pop_growth_mode = "perc" , pop_growth_perc = .01, 
    inc_growth_mode = "random_agent_replication", pop_growth_inc_perc = .90, inc_growth_perc = .05, 
    perc_move = 0.025, house_choice_mode = "simple_avoidance_utility", 
    simple_anova_coefficients = [-121428, 294707, 130553, 128990, 154887], flood_coefficient = -500000, budget_reduction_perc = .90,
    stock_increase_mode = "simple_perc",  stock_increase_perc = .05,  housing_pricing_mode = "simple_perc", price_increase_perc = .05,
    levee = false, breach = true, breach_null = 0.45, risk_averse = 0.3, flood_mem = 10, fixed_effect = 0, seed = 1500,
)

    flood_rng = MersenneTwister(seed)
    f_matrix, f_dict = initialize_flood(flood_rng, base_df, levee_df; no_of_years = no_of_years, slr_scen = slr_scen, slr_rate = slr_rate, levee = levee, 
    breach = breach, breach_null = breach_null, gev_d = default_gev)

    #Utility Matrix 
    u_matrix = zeros(size(bg_df)[1],3,3)
    #Move Matrix
    p_matrix = zeros(size(bg_df)[1],3,3)

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
    u_matrix, p_matrix, f_matrix, f_dict, no_of_years, 0)

    model = ABM(
        Union{BlockGroup, House, HHAgent},
        space,
        scheduler = Schedulers.ByType((BlockGroup, House, HHAgent), false),
        model_step! = model_evolve,
        properties = parameters,
        rng = MersenneTwister(seed),
        warn = false,
    )

    #Create block group agents (network nodes)
    #AgentsIO.populate_from_csv!(model, filename, add_bg; row_number_is_id = true)
    for row in Tables.namedtupleiterator(model.df)
        add_agent_single!(add_bg(row), model)
    end
    
    #Create housing demand record for House agents
    demand_record = repeat([false], no_of_years)

    #Create Household agents and add to block groups
    housing_df = DataFrame(name = Any[], no_hh_agents  = Any[], population = Int64[], average_income = Float64[], avg_hh_size = Float64[], 
    pop_density = Float64[], occupied_units = Int64[], available_units = Int64[])

    for bg in collect(allagents(model))
        #Assign BG flood area value based on 100 year event (7th column of matrix is 100 yr event)
        bg.perc_fld_area = model.flood_matrix[bg.id,7,1]
        
        if bg.hhsize90 != 0.0 && isfinite(bg.hhsize90)
            no_of_hhs = round(bg.pop90 / bg.hhsize90)
            #no_of_agents = fld(fld(no_of_hhs + no_hhs_per_agent, 2), no_hhs_per_agent) #division with rounding to nearest integer
            no_of_agents = fld(no_of_hhs, no_hhs_per_agent)
            #bg.population = Int(round(no_of_agents * no_hhs_per_agent * bg.hhsize90))
            bg.population = bg.pop90

        else  # if hh size is 0.0 or nan (i.e., data error) using median household size for population
            bg.hhsize90 = median(skipmissing(model.df.hhsize1990))

            no_of_hhs = round(bg.pop90 / bg.hhsize90)
            #no_of_agents = fld(fld(no_of_hhs + no_hhs_per_agent, 2), no_hhs_per_agent) #division with rounding to nearest integer
            no_of_agents = fld(no_of_hhs, no_hhs_per_agent)
            #bg.population = Int(round(no_of_agents * no_hhs_per_agent * bg.hhsize90))
            bg.population = bg.pop90
        end

        #add occupied unit to associated block group node 
        bg.occupied_units = no_of_agents
        #Calculate available_units for associated block group 
        bg.available_units = round((initial_vacancy * no_of_agents) / (1 - initial_vacancy))

        for a in 1:3
            agent_pop = ceil(Int,no_of_agents/3)
            avail_units = ceil(Int,bg.available_units/3)
            #Decide where agents are living (TEMPORARY)
            houses = zeros(3)
            houses[a] = agent_pop
            #Add agent to model
            add_agent!(bg.pos, HHAgent, model, bg.id, no_hhs_per_agent, Int(round(bg.hhsize90)),a, 
            Float64(bg.mhi90), agent_pop * no_hhs_per_agent * Int(round(bg.hhsize90)), houses[1], houses[2], houses[3], 0, agent_pop, simple_avoidance_perc)
            #Houses
            add_agent!(bg.pos, House, model, bg.id, a, demand_record, agent_pop, avail_units,
             agent_pop + avail_units, bg.new_price)
        end

        #Calculate BG statistics based on agent properties within each BG
        #Future: Set income/size to NaN if avg == 0 (no agents in block group) 
        bg.avg_hh_income = mean([a.income for a in agents_in_position(bg.pos, model) if a isa HHAgent])
        bg.avg_hh_size = mean([a.hh_size for a in agents_in_position(bg.pos, model) if a isa HHAgent])

        bg.pop_density = bg.population / bg.area 
        
        #add to dataframe 
        push!(housing_df, [bg.id, no_of_hhs, bg.population, bg.avg_hh_income, bg.avg_hh_size, bg.pop_density, bg.occupied_units, bg.available_units])
    end
    

    #model.avg_hh_income = mean([a.income for a in allagents(model) if a isa HHAgent])
    #model.avg_hh_size = mean([a.hh_size for a in allagents(model) if a isa HHAgent])
    model.total_population = sum([a.population for a in allagents(model) if a isa HHAgent])

    # calculate normalized statistics for block groups
    housing_df[!,"average_income_norm"] = housing_df[!, "average_income"] / maximum(filter(!isnan,housing_df.average_income))

    # merge with housing_df with model.df to retain geometry features.
    model.df = leftjoin(model.df, housing_df, on = "fid_1" => "name")
    sort!(model.df, :fid_1)

    return model
end

