

function NewAgentCreation(model::ABM; growth_mode = "perc", growth_rate = 0.01, inc_growth_mode = "random_agent_replication",
    pop_growth_inc_perc = 0.90, inc_growth_perc = 0.05, no_hhs_per_agent = 10, hh_size = 2.7,
     simple_avoidance_perc = 0.10, house_budget_mode = "rhea", hh_budget_perc = 0.33)
    #**Args**:
    #    growth_mode (string): defined as either "perc" or "exog" depending upon simulation mode
    #    growth_rate (float): if growth_mode = "perc", defines the annual percentage population growth rate
    #    growth_inc (float): if growth_mode = "perc", defines the increase in the mean income for incoming population

    #Set position to add new agents
    new_pos = model[-1].pos 

    if growth_mode == "perc"
        new_population = model.total_population * growth_rate
        no_new_agents = fld(((new_population / hh_size) + fld(no_hhs_per_agent, 2)), no_hhs_per_agent)

        if inc_growth_mode == "normal distribution"
            #Calculate "mean,std from average income norm column"
            mu = mean(model.df[:, "average_income_norm"]) * (1 + inc_growth_perc)
            sigma = std(model.df[:, "average_income_norm"])
            #Create truncated normal distribution to sample future income values 
            X = truncated(Normal(mu,sigma), 5000, 300000)

            for a in 1:Int(no_new_agents)
                ##Create new agent
                #Sample income
                hh_income = rand(model.rng, X)
                #calculate budget
                if house_budget_mode == "rhea"
                    hh_budget = exp(4.96 + (0.63 * log(Float64(hh_income))))
                elseif house_budget_mode == "perc"
                    hh_budget = Float64(hh_income) * hh_budget_perc
                end
                #Determine avoidance
                agent_avoid = rand(model.rng,Uniform(0,1)) <= simple_avoidance_perc ? true : false
                migrant = HHAgent(nextid(model), new_pos, -1, no_hhs_per_agent, Int(round(hh_size)), hh_income, house_budget_mode, model.tick, simple_avoidance_perc,
                 agent_avoid, hh_budget, hh_budget_perc)

                ##Add agent to unassigned queue
                add_agent_pos!(migrant, model)
            end

        elseif inc_growth_mode == "percentile_based"

            for a in 1: Int(no_new_agents)
                ##Create new agent
                #Sample income
                hh_income = quantile(filter(!isnan,model.df.average_income), pop_growth_inc_perc)
                #Calculate budget
                if house_budget_mode == "rhea"
                    hh_budget = exp(4.96 + (0.63 * log(Float64(hh_income))))
                elseif house_budget_mode == "perc"
                    hh_budget = Float64(hh_income) * hh_budget_perc
                end
                #Determine avoidance
                agent_avoid = rand(model.rng,Uniform(0,1)) <= simple_avoidance_perc ? true : false
                migrant = HHAgent(nextid(model), new_pos, -1, no_hhs_per_agent, Int(round(hh_size)), hh_income, house_budget_mode, model.tick, simple_avoidance_perc,
                 agent_avoid, hh_budget, hh_budget_perc)

                ##Add agent to unassigned queue
                add_agent_pos!(migrant, model)
            end

        elseif inc_growth_mode == "random_agent_replication"

            for a in 1: Int(no_new_agents)
                rand_agent = random_agent(model, x-> x isa HHAgent)
                hh_income = rand_agent.income
                hh_budget = rand_agent.house_budget
                agent_avoid = rand(model.rng,Uniform(0,1)) <= simple_avoidance_perc ? true : false
                migrant = HHAgent(nextid(model), new_pos, -1, no_hhs_per_agent, Int(round(hh_size)), hh_income, house_budget_mode, model.tick, simple_avoidance_perc,
                 agent_avoid, hh_budget, hh_budget_perc)

                ##Add agent to unassigned queue
                add_agent_pos!(migrant, model)
            end
        
        end
    end
end