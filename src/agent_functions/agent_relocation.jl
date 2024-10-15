function ExistingAgentResampler(agent::HHAgent, model::ABM; perc_move = 0.10)
    residents = [agent.occ_low, agent.occ_mid, agent.occ_high]
    agents_moving = rand.(abmrng(model), Binomial.(residents, perc_move)) #number of households wanting to move from each housing type 
    no_of_agents_moving = sum(agents_moving) #total number of households moving from this HHAgent type
    if no_of_agents_moving < 1
    #not enough agents
        return
    end

    #Update number of agents moving 
    setproperty!(agent, :n_move, no_of_agents_moving)
    setproperty!(agent, :n_stay, agent.n_stay - no_of_agents_moving)
    #Update HHagent occupation categories
    agent.occ_low -= agents_moving[1]
    agent.occ_mid -= agents_moving[2]
    agent.occ_high -= agents_moving[3]
    #Update occupied and available_units for associated Houses
    house_agents = [a for a in agents_in_position(agent, model) if a isa House]
    for house in house_agents
        house.occupied_units -= agents_moving[house.quality]
        house.available_units += agents_moving[house.quality]
    end
    
    
    #agent.population -= sum(getproperty.(agents_moving,:no_hhs_per_agent) .* getproperty.(agents_moving,:hh_size))
end

function AgentMove!(agent::BlockGroup, model::ABM; levee = false, risk_averse = 0.3, mem = 10, base_prob = 0.10, f_e = 0)
    """Function determines probability of agent action
    using a risk aversion function.
    Output updates agent's action property""" 
    ### Calculate logistic Probability ###
   
    #Fixed effect: define scaling factor depending on levee presence
    scale_factor = levee ? 0.1 - f_e : 0.1
    #Calculate flood probability based on risk averse value
    if agent.flood_hazard == 0
        flood_prob = base_prob
    elseif risk_averse == 0
        #flood_prob = 1/(1+ exp(-20((sum(model[calc_house].flood[time_back])/mem) - 0.1)))
        flood_prob = 1/(1+ exp(-20((agent.flood_hazard/mem) - 0.1)))  + base_prob
    elseif risk_averse == 1
        flood_prob = 0
    else
        #flood_prob = 1/(1+ exp(-10((sum(model[calc_house].flood[time_back])/mem) - model.risk_averse)))
        flood_prob = 1/(1+ exp(-((agent.flood_hazard/mem) - risk_averse)/scale_factor)) + base_prob
    end
     
    move_prob = flood_prob <= 1.0 ? flood_prob : 1
    
    ### Calculate number of from each HHAgent category ###

    bg_agents = [a for a in agents_in_position(agent, model) if a isa HHAgent]
    for hhagent in bg_agents
        ExistingAgentResampler(hhagent, model; perc_move = move_prob)
    end
    
end


function calc_utility(agent::BlockGroup, model::ABM; anova_coef = [-121428, 294707, 130553, 128990, 154887], flood_coef = -500000)
    #Determine if flood disamenity is reduced from levee presence
    #scale_factor = levee ? 1.0 - (10 * f_e) : 1.0
    row = model.df[agent.id, :]
    util = anova_coef[1] + (anova_coef[2] * row.N_MeanSqfeet) + (anova_coef[3] * row.N_MeanAge) + (anova_coef[4] * row.N_MeanNoOfStories) + 
    (anova_coef[5] * row.N_MeanFullBathNumber) + (flood_coef * (agent.flood_hazard/model.relo_sampler[:mem])) + (1 * row.residuals)

    model.hh_utilities[agent.id,:,:] = repeat([util * 0.75, util, util * 1.25], 1, 3)'
end 

## Functions to update Agent attributes after Agent Sorting

function relo_update!(agent::HHAgent, relo_mat::Array)
    b_g = agent.bg_id
    pop_group = agent.inc_cat
    agent.occ_low += relo_mat[b_g, 1, pop_group]
    agent.occ_mid += relo_mat[b_g, 2, pop_group]
    agent.occ_high += relo_mat[b_g, 3, pop_group]

    new_pop = agent.occ_low + agent.occ_mid + agent.occ_high

    setproperty!(agent, :population, new_pop * agent.no_hhs_per_agent * agent.hh_size)
    setproperty!(agent, :n_move, 0)
    setproperty!(agent, :n_stay, new_pop)


end

function relo_update!(agent::House, relo_mat::Array)
    b_g = agent.bg_id
    house_group = agent.quality

    agent.occupied_units += sum(relo_mat[b_g, house_group, :])
    agent.available_units -= sum(relo_mat[b_g, house_group, :])

    @assert agent.occupied_units + agent.available_units == agent.capacity
end


"""
functions NewAgentLocation and ExistingAgentLocation in the python version of CHANCE-C are recreated with function AgentLocation. 


function AgentLocation(agent::Queue, model::ABM; levee = false, f_e = 0.0, bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
    budget_reduction_perc = 0.10, a_c = [-121428, 294707, 130553, 128990, 154887], f_c = -500000)
    #Create dataframe to store potential relocation bgs
    bg_sample = DataFrame(hh_id = Int64[], bg_id = Int64[], bg_utility = Float64[])
    for hh_agent in agents_in_position(agent, model)
        if !isa(hh_agent, HHAgent)
            continue
        else
            if house_choice_mode == "simple_avoidance_utility"
                if hh_agent.avoidance
                    bg_budget = subset(model.df, :perc_fld_area => n -> n .<= 0.10)#, :new_price => n -> n .<= hh_agent.house_budget) #does new_price <= house_budget?
                else
                    bg_budget = subset(model.df, :new_price => n -> n .<= hh_agent.house_budget)
                end
            elseif house_choice_mode == "budget_reduction"
                #Calculate new budget for flooded areas
                new_house_budget = hh_agent.house_budget * (1 - budget_reduction_perc)
                #Create vector of household budgets conditional on BlockGroup flooded area 
                hh_budget = ifelse.(model.df.perc_fld_area .>= 0.10, new_house_budget, hh_agent.house_budget)
                bg_budget = subset(model.df, :new_price => n -> n .<= hh_budget)
            else 
                bg_budget = subset(model.df, :new_price => n -> n .<= hh_agent.house_budget)
            end
        end
        #Sample from bg_budget for possible new locations 
        try
            #calculate sample weights
            weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
            bg_options = bg_budget[sample(model.rng, 1:nrow(bg_budget), weights, 10; replace = true), :] 
            #Calculate utility of options for household agents
            bg_utilities = calc_utility.(eachrow(bg_options), house_choice_mode, levee, f_e, Ref(model); anova_coef = a_c, flood_coef = f_c) #Figure out most efficient way to calculate. Maybe just read in entire dataframe instead of iterating over rows
            #push to bg_sample dataframe
            append!(bg_sample.hh_id,repeat([hh_agent.id],bg_sample_size))
            append!(bg_sample.bg_id, bg_options.fid_1)
            append!(bg_sample.bg_utility, bg_utilities)
        catch
            #HHAgent can't afford any locations. Assume outmigration and remove agent
            remove_agent!(hh_agent, model)
        end
    end
    append!(model.hh_utilities_df, bg_sample)
end
"""