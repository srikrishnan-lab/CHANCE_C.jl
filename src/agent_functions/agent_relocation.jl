function ExistingAgentResampler(agent::BlockGroup, model::ABM; perc_move = 0.10)
    bg_agents = [a for a in agents_in_position(agent, model) if a isa HHAgent]
    no_of_agents_moving = Int(round(perc_move * length(bg_agents))) #number of HHAgents moving from BlockGroup
    if no_of_agents_moving < 1
    #not enough agents
        return
    end
    agents_moving = sample(model.rng, bg_agents, no_of_agents_moving; replace = false) #Randomly sampled agents that will move
    #Update BG id property for moving agents
    setproperty!.(agents_moving, :bg_id, 0)
    #Move agents to relocating Queue
    move_agent!.(agents_moving, Ref(model[0].pos), Ref(model))
    #Update occupied and available_units bg properties
    agent.occupied_units -= no_of_agents_moving
    agent.available_units += no_of_agents_moving
    
    agent.population -= sum(getproperty.(agents_moving,:no_hhs_per_agent) .* getproperty.(agents_moving,:hh_size))
end

function calc_utility(row, house_choice_mode; cd_dict = Dict(:a=>0.4,:b=>0.4,:c=>0.2), anova_coef = [-121428, 294707, 130553, 128990, 154887], flood_coef = -500000)
    if house_choice_mode == "cobb_douglas_utility"
        util = row.average_income_norm ^ cd_dict[:a] * row.prox_cbd_norm ^ cd_dict[:b] * row.flood_risk_norm ^ cd_dict[:c]

    elseif house_choice_mode == "simple_flood_utility"
        util = anova_coef[1] + (anova_coef[2] * row.N_MeanSqfeet) + (anova_coef[3] * row.N_MeanAge) + (anova_coef[4] * row.N_MeanNoOfStories) + 
        (anova_coef[5] * row.N_MeanFullBathNumber) + (flood_coef * row.perc_fld_area) + (1 * row.residuals)

    else #house_choice_mode == "simple_anova_utility" or house_choice_mode == "budget_reduction" or house_choice_mode == "simple_avoidance_utility"
        util = anova_coef[1] + (anova_coef[2] * row.N_MeanSqfeet) + (anova_coef[3] * row.N_MeanAge) + (anova_coef[4] * row.N_MeanNoOfStories) + 
        (anova_coef[5] * row.N_MeanFullBathNumber) + (1 * row.residuals)
    end
    return util 
end

"""
functions NewAgentLocation and ExistingAgentLocation in the python version of CHANCE-C are recreated with function AgentLocation. 
"""

function AgentLocation(agent::Queue, model::ABM; bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
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
            bg_utilities = calc_utility.(eachrow(bg_options), house_choice_mode; anova_coef = a_c, flood_coef = f_c) #Figure out most efficient way to calculate. Maybe just read in entire dataframe instead of iterating over rows
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