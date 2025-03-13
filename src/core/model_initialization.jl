

mutable struct Properties{df<:Union{DataFrame, GroupedDataFrame{DataFrame}}, t_p<:Int64, f_h<:Dict, a_c<:Dict, r_s<:Dict, a_r<:Dict, b_d<:Dict,
     h_p<:Dict, u_hhs<:DataFrame, no_y<:Int64, f_mat<:Array, f_dict<:Dict, tick<:Int64}
    df::df
    total_population::t_p
    flood_hazard::f_h
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


function Simulator(bg_df, pop_df, f_matrix, f_dict, model_evolve; 
    no_of_years = 10, no_hhs_per_agent=10, simple_avoidance_perc = 0.95, house_budget_mode = "rhea", hh_budget_perc = 0.33, grouped = false, group_col = "adj_income_2019",
    cutoff_dict = OrderedDict("low"=> [0,25000.00], "medium"=>[25000.00,75000.00], "high"=>[75000.00, 1e7]), bg_cat = Dict(:col =>"income_cat", :group => ["low", "medium", "high"]), hh_size = 2.7, 
    pop_growth_mode = "perc", pop_growth_perc = .01, dist_param = [0.3, 0.4, 0.3], inc_growth_mode = "random_agent_replication", pop_growth_inc_perc = .90, inc_growth_perc = .05, perc_move = 0.025,
    house_choice_mode = "simple_avoidance_utility", simple_anova_coefficients = [-121428, 294707, 130553, 128990, 154887], flood_coefficient = -500000, budget_reduction_perc = .90,
    penalty = -50, stock_increase_mode = "simple_perc",  stock_increase_perc = .05,  housing_pricing_mode = "simple_perc", price_increase_perc = .05,
    levee = false, risk_averse = 0.3, flood_mem = 10, fixed_effect = 0, seed = 1500,
)

    
    ##Create Keyword Arguments for step function parameters
    #Agent relocation
    flood_hazard = Dict(:mem => flood_mem, :levee => levee, :f_e => fixed_effect, :flood_coef => flood_coefficient)
    #AgentCreation
    agent_creation = Dict(:growth_rate => pop_growth_perc)

    #Agent relocation
    averse_move = Dict(:category => bg_cat[:group], :levee => levee, :risk_averse => risk_averse, :mem => flood_mem, :base_prob => perc_move, :f_e => fixed_effect)
    agent_relocate = Dict(:levee => levee, :f_e => fixed_effect, :house_choice_mode => house_choice_mode, :bg_sample_size => no_hhs_per_agent, :budget_reduction_perc => budget_reduction_perc,
    :penalty => penalty, :migrate_prob => perc_move)

    #BuildingDevelopment
    build_develop = Dict(:stock_increase_mode => stock_increase_mode, :stock_increase_perc => stock_increase_perc)

    #HousingPricing
    house_price = Dict(:housing_pricing_mode => housing_pricing_mode, :price_increase_perc => price_increase_perc)

    #Set space for model 
    if grouped
        grouped_df = groupby(bg_df, :GEOID)
        width = Int(ceil(sqrt(size(grouped_df)[1])))
        space = GridSpace((width,width))
    else
        width = Int(ceil(sqrt(size(bg_df)[1])))
        space = GridSpace((width,width))
    end

    parameters = Properties(bg_df, 0, flood_hazard, agent_creation, averse_move, agent_relocate, build_develop, house_price,
     DataFrame(hh_id = Int64[], bg_id = Int64[], GEOID = Int64[], cat = String[], bg_utility = Float64[]), no_of_years, f_matrix, f_dict, 0)

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
    if grouped
        for (id,group) in enumerate(grouped_df)
            add_agent_single!(create_bg_phil(group, no_of_years; agent_id = id, categories = bg_cat[:group], house_choice_mode = house_choice_mode, 
            simple_anova_coefficients = simple_anova_coefficients), model)
        end
    else
        for row in Tables.namedtupleiterator(model.df)
            add_agent_single!(create_bg_phil(row, no_of_years), model)
        end
    end
    
    #Create Household agents and add to block groups
    housing_df = DataFrame(name = Int64[], agent_id = Int64[], no_hh_agents  = Any[], population = Int64[], average_income = Float64[], avg_hh_size = Float64[], 
    pop_density = Float64[], group = String[], occupied_units = Int64[], available_units = Int64[], demand_exceeds_supply = Bool[])

    for bg in collect(allagents(model))
        dict, agent_df = agent_bin_cont(bg.GEOID, pop_df; no_hhs_per_agent=no_hhs_per_agent, group_col = group_col, cutoffs = cutoff_dict,
         house_budget_mode = house_budget_mode, hh_budget_perc = hh_budget_perc)
        
        no_of_hhs = sum(agent_df.nrow)
        for row in Tables.namedtupleiterator(agent_df)
            # indicate whether agent avoids flood zone (used in "simple avoidance utility" model)
            agent_avoid = rand(abmrng(model),Uniform(0,1)) <= simple_avoidance_perc ? true : false

            #Add agent to model
            add_agent!(bg.pos, HHAgent, model, bg.id, row.nrow, row.cat, row.race, Int(round(row.avg_hh_size)), 
            Float64(row.avg_income), Dict(bg.id => bg.current_utility[row.cat]), house_budget_mode, model.tick, simple_avoidance_perc, agent_avoid, row.budget, hh_budget_perc)
        end
        #Calculate BG statistics based on agent properties within each BG
        #Future: Set income/size to NaN if avg == 0 (no agents in block group) 
        bg.avg_hh_income = dict[:avg_inc]
        bg.avg_hh_size = dict[:avg_hh_size]

        bg.population = dict[:total_pop]
        bg.pop_density = bg.population / bg.area
        #add occupied unit to associated block group node
        if typeof(bg.occupied_units) == Int64 
            bg.occupied_units = dict[:occupied]
            #Calculate available_units for associated block group 
            bg.available_units = dict[:vacant]
            
        elseif typeof(bg.occupied_units) == Dict{String, Int64}
            occ_dict = Dict(k => length([a for a in agents_in_position(bg, model) if a isa HHAgent && a.group == k]) for k in keys(bg.occupied_units))
            bg.occupied_units = occ_dict
            #Calculate available_units for associated block group 
            total_prop = sum(values(bg.available_units))
            vac_dict = Dict(k => Int(round((v/total_prop) * dict[:vacant])) for (k,v) in bg.available_units)
            bg.available_units = vac_dict

        end
        
        ## add to dataframe 
        for group in bg_cat[:group]
            push!(housing_df, [bg.GEOID, bg.id, no_of_hhs, bg.population, bg.avg_hh_income, bg.avg_hh_size, bg.pop_density, group, bg.occupied_units[group], bg.available_units[group], bg.demand_exceeds_supply[group][1]])
        end
    end
    
    ##Create nodes to store relocating/unassigned agents
    #For relocating agents
    add_agent_single!(Relocating(0,(0,0)), model)
    #For unassigned agents (for new agent creation)
    add_agent_single!(Unassigned(-1,(0,0)), model)
    new_agent_df = NewAgentCreation(pop_df, model; no_of_years = no_of_years, growth_rate = pop_growth_perc, dist_param = dist_param, group_col = "adj_income_2019",
    cutoffs = cutoff_dict, no_hhs_per_agent = no_hhs_per_agent, house_budget_mode = house_budget_mode, hh_budget_perc = hh_budget_perc)

    for row in Tables.namedtupleiterator(new_agent_df)
        # indicate whether agent avoids flood zone (used in "simple avoidance utility" model)
        agent_avoid = rand(abmrng(model),Uniform(0,1)) <= simple_avoidance_perc ? true : false

        #Add agent to model
        add_agent!(model[-1].pos, HHAgent, model, -1, row.nrow, row.cat, row.race, Int(round(row.avg_hh_size)), 
        Float64(row.avg_income), Dict(-1 => 0.0), house_budget_mode, model.tick, simple_avoidance_perc, agent_avoid, row.budget, hh_budget_perc)
    end

    #model.avg_hh_income = mean([a.income for a in allagents(model) if a isa HHAgent])
    #model.avg_hh_size = mean([a.hh_size for a in allagents(model) if a isa HHAgent])
    model.total_population = sum([a.population for a in allagents(model) if a isa BlockGroup])

    # calculate normalized statistics for block groups
    housing_df[!,"average_income_norm"] = housing_df[!, "average_income"] / maximum(filter(!isnan,housing_df.average_income))

    # merge with housing_df with model.df to retain geometry features
    model.df = leftjoin(model.df, housing_df, on = ["GEOID" => "name", bg_cat[:col] => "group"])

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
