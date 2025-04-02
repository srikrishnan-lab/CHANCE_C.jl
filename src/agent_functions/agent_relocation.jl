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
"""
function agent_prob!(agent::BlockGroup, model::ABM; category = [1,2,3], levee = false, risk_averse = 0.3, mem = 10, base_prob = 0.10, f_e = 0)
    #Function determines probability of agent action
    #using a risk aversion function.
    #Output updates agent's action property
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
    
    ### Move triggered agents to Queue ###

    bg_agents = [a for a in agents_in_position(agent, model) if a isa HHAgent]
    agents_moving = bg_agents[Bool.(rand(abmrng(model), Binomial(1,move_prob),length(bg_agents)))] #HHAgents moving from BlockGroup
    no_of_agents_moving = length(agents_moving)

    if no_of_agents_moving < 1
    #not enough agents
        return
    end

    #Update BG id property for moving agents
    setproperty!.(agents_moving, :bg_id, 0)
    #Move agents to relocating Queue
    move_agent!.(agents_moving, Ref(model[0].pos), Ref(model))
    #Update occupied and available_units bg properties
    for cat in category
        agents_in_group = length([a for a in agents_moving if a.group == cat])
        agent.occupied_units[cat] -= agents_in_group
        agent.available_units[cat] += agents_in_group
    end
    
    agent.population -= sum(getproperty.(agents_moving,:no_hhs_per_agent) .* getproperty.(agents_moving,:hh_size))
    
end
"""

function agent_prob!(agent::HHAgent, model::ABM; levee = false, risk_averse = 0.3, base_prob = 0.10, f_e = 0)
    """Function determines probability of agent action
    using a risk aversion function.
    Output updates agent's action property""" 
    
    ### Calculate logistic Probability ###
   
    #Fixed effect: define scaling factor depending on levee presence
    scale_factor = levee ? 0.1 - f_e : 0.1
    #Calculate flood probability based on risk averse value
    if agent.flood_experience == 0
        flood_prob = base_prob
    elseif risk_averse == 0
        flood_prob = 1/(1+ exp(-20((agent.flood_experience) - 0.1))) + base_prob
    elseif risk_averse == 1
        flood_prob = 0
    else
        flood_prob = 1/(1+ exp(-((agent.flood_experience) - risk_averse)/scale_factor)) + base_prob
    end
     
    move_prob = flood_prob <= 1.0 ? flood_prob : 1
    
    ### Move triggered agent to Queue ###
    if Bool(rand(abmrng(model), Binomial(1,move_prob)))
        #Get Block Group id of agent's location
        bg_id = first(keys(agent.utility))
        setproperty!(agent, :bg_id, 0)
        #Move agents to relocating Queue
        move_agent!(agent, model[0].pos, model)
        model[bg_id].occupied_units[agent.occ_cat] -= 1
        model[bg_id].available_units[agent.occ_cat] += 1

        model[bg_id].population -= getproperty(agent,:no_hhs_per_agent) * getproperty(agent,:hh_size)
    end
end

"""
functions NewAgentLocation and ExistingAgentLocation in the python version of CHANCE-C are recreated with function AgentLocation. 
"""
function AgentLocation(agent::Queue, model::ABM; levee = false, f_e = 0.0, bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
    budget_reduction_perc = 0.10, penalty = 50)

    if agent.type == :relocating
        loc_df = copy(model.df)
        # Create a GEOID-to-BlockGroup lookup
        geoid_to_bg = Dict{Int64, Int64}()
        for bg in allagents(model)
            if bg isa BlockGroup
                geoid_to_bg[bg.GEOID] = bg.id
            end
        end

        # Use view or filter instead of multiple list comprehensions
        moving_agents = sort!([a for a in agents_in_position(agent, model) if a isa HHAgent], by=a -> a.income, rev=true)

        current_index = 1
        #Preallocate some vectors to reduce memory allocations
        hh_ids = Vector{Int64}(undef, bg_sample_size * length(moving_agents))
        bg_ids = Vector{Int64}(undef, bg_sample_size * length(moving_agents))
        bg_GEOID = Vector{Int64}(undef, bg_sample_size* length(moving_agents))
        bg_cat = Vector{Int64}(undef, bg_sample_size* length(moving_agents))
        bg_utilities = Vector{Float64}(undef, bg_sample_size * length(moving_agents))

        for hh_agent in moving_agents
            # Consolidate budget selection logic
            bg_budget = if house_choice_mode == "simple_avoidance_utility"
                hh_agent.avoidance ? 
                    subset(loc_df, :perc_fld_area => n -> n .<= 0.10, view = true) :
                    subset(loc_df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true, view = true)
            elseif house_choice_mode == "budget_reduction"
                new_house_budget = hh_agent.house_budget * (1 - budget_reduction_perc)
                hh_budget = ifelse.(loc_df.perc_fld_area .>= 0.10, new_house_budget, hh_agent.house_budget)
                subset(loc_df, :market_value => n -> n .<= hh_budget, skipmissing=true, view = true)
            else
                subset(loc_df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true, view = true)
            end


            # Use a more efficient sampling approach
            util_diff = 0
            try
                # Precompute weights to avoid repeated calculations
                weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
                    
                # Check for available locations more efficiently
                valid_locations = findall(weights .> 0)
                if isempty(valid_locations)
                    throw(ErrorException("No affordable locations with available units"))
                end

                #Sample from affordable locations based on weights
                sample_size = min(length(valid_locations), bg_sample_size)
                sampled_indices = sample(abmrng(model), valid_locations, sample_size, replace=false)
                
                #Grab utilities from sampled locations
                loc_utilities = [model[geoid_to_bg[row.GEOID]].current_utility[row.income_cat] + ((row.income_cat - hh_agent.group) * penalty) for row in eachrow(bg_budget[sampled_indices, [:GEOID, :income_cat]])]
                # Find indices of block groups with better utilities than current agent location
                current_utility = first(values(hh_agent.utility))
                util_diff = (current_utility - maximum(loc_utilities)) / current_utility
                opt_locs = findall(>(current_utility), loc_utilities)

                # Check if any moves are possible
                if isempty(opt_locs)
                    throw(ErrorException("No better locations found"))
                end
                best_indices = sampled_indices[opt_locs]
                
                #Append future block group properties to vectors
                ind_length = length(best_indices)

                copyto!(hh_ids, current_index, fill(hh_agent.id, ind_length), 1, ind_length)
                copyto!(bg_ids, current_index, getindex.(Ref(geoid_to_bg), bg_budget[best_indices,:GEOID]), 1, ind_length)
                copyto!(bg_GEOID, current_index, bg_budget[best_indices, :GEOID], 1, ind_length)
                copyto!(bg_cat, current_index, bg_budget[best_indices, :income_cat], 1, ind_length)
                copyto!(bg_utilities, current_index, loc_utilities[opt_locs], 1, ind_length)

                current_index += ind_length
                
            catch
                # Migration logic remains similar
                last_bg = model[first(keys(hh_agent.utility))]
                if last_bg.id == -1
                    remove_agent!(hh_agent, model)
                    continue
                end

                stay_prob = 1.5/(1+ exp(-0.6(util_diff)))
                stay_prob = stay_prob <= 1.0 ? stay_prob : 1.0
                if rand(abmrng(model), Binomial(1, stay_prob)) == 1
                    #Revert HHAgent Properties
                    setproperty!(hh_agent, :bg_id, last_bg.id)
                    move_agent!(hh_agent, last_bg.pos, model)
                    #Update Last BG Properties
                    last_bg.occupied_units[hh_agent.occ_cat] += 1
                    last_bg.available_units[hh_agent.occ_cat] -= 1
                    last_bg.population += getproperty(hh_agent, :no_hhs_per_agent) * getproperty(hh_agent, :hh_size)
                else
                    remove_agent!(hh_agent, model)
                end
            end
        end
        
        ##Create df from vectors, append to model properties df
        #Remove extra undef values by using current index
        bg_sample = DataFrame(hh_id = hh_ids[1:current_index-1], bg_id = bg_ids[1:current_index-1], 
        GEOID = bg_GEOID[1:current_index-1], cat = bg_cat[1:current_index-1], bg_utility = bg_utilities[1:current_index-1])
        
        append!(model.hh_utilities_df, bg_sample)
    else
        return 
    end
end

"""
function AgentLocation(agent::Queue, model::ABM; levee = false, f_e = 0.0, bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
    budget_reduction_perc = 0.10, penalty = 50, migrate_prob = 0.05)
    #Create dataframe to store potential relocation bgs
    bg_sample = DataFrame(hh_id = Int64[], bg_id = Int64[], GEOID = Int64[], cat = String[], bg_utility = Float64[])
    moving_agents = sort!([a for a in agents_in_position(agent, model) if a isa HHAgent], by=a -> a.income, rev=true)
    bg_options = DataFrame()
    for hh_agent in moving_agents
        if house_choice_mode == "simple_avoidance_utility"
            if hh_agent.avoidance
                bg_budget = subset(model.df, :perc_fld_area => n -> n .<= 0.10)#, :new_price => n -> n .<= hh_agent.house_budget) #does new_price <= house_budget?
            else
                bg_budget = subset(model.df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true)
            end
        elseif house_choice_mode == "budget_reduction"
            #Calculate new budget for flooded areas
            new_house_budget = hh_agent.house_budget * (1 - budget_reduction_perc)
            #Create vector of household budgets conditional on BlockGroup flooded area 
            hh_budget = ifelse.(model.df.perc_fld_area .>= 0.10, new_house_budget, hh_agent.house_budget)
            bg_budget = subset(model.df, :market_value => n -> n .<= hh_budget, skipmissing=true)
        else 
            bg_budget = subset(model.df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true)
        end
    
        #Sample from bg_budget for possible new locations 
        #calculate sample weights
        try
            weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
            if sum(weights .> 0) == 0 #Affordable locations have no available units
                throw(error()) 
            end
            #check and see if there are at least 10 locations with available units in budget df
            if sum(weights .> 0) >= bg_sample_size 
                bg_options = bg_budget[sample(abmrng(model), 1:nrow(bg_budget), weights, bg_sample_size; replace = false), :]
            else #If not, just select locations with available units
                bg_options = bg_budget[weights .> 0, :]
            end
            
            #Collect utilities of options for household agents
            bg_ids = Int64[]
            bg_GEOID = Int64[]
            bg_cat = String[] 
            bg_utilities = Float64[]
            for row in eachrow(bg_options)
                bg_sel = [bg for bg in collect(allagents(model)) if bg isa BlockGroup && bg.GEOID == row.GEOID][1]
                bg_util = getindex(getproperty(bg_sel, :current_utility), row.income_cat)
                push!(bg_ids, bg_sel.id)
                push!(bg_GEOID, row.GEOID)
                push!(bg_cat, row.income_cat)
                push!(bg_utilities, bg_util)
            end
            #new_bgs = [bg for bg in allagents(model) if bg isa BlockGroup && bg.GEOID in bg_options.GEOID]
            #bg_ids = getproperty.(new_bgs, :id)
            #bg_GEOID = getproperty.(new_bgs, :GEOID)
            #bg_cat = 
            #bg_utilities = getindex.(getproperty.(new_bgs, :current_utility), bg_options.income_cat)
            #push to bg_sample dataframe
            move_df = DataFrame(hh_id = repeat([hh_agent.id],length(bg_ids)), bg_id = bg_ids, GEOID = bg_GEOID, cat = bg_cat, bg_utility = bg_utilities)
            #check if new location utilities are greater than current bg_utility
            move_df = move_df[move_df.bg_utility .> collect(values(hh_agent.utility))[1], :]
            #If available locations' utilities are less than existing utility:
            if nrow(move_df) < 1
                throw(error())
            else
            bg_sample = vcat(bg_sample, move_df)
            end

        catch
            #HHAgent can't afford any locations. See if agent returns to BG or outmigrates
            if Bool(rand(abmrng(model), Binomial(1, migrate_prob)))
                last_bg = model[collect(keys(hh_agent.utility))[1]]
                move_agent!(hh_agent, last_bg.pos, model)
                last_bg.occupied_units[hh_agent.group] += 1
                last_bg.available_units[hh_agent.group] -= 1

                last_bg.population += getproperty(hh_agent,:no_hhs_per_agent) * getproperty(hh_agent,:hh_size)
            else
                remove_agent!(hh_agent, model)
            end
            #remove_agent!(hh_agent, model)
            continue
        end
    end
    append!(model.hh_utilities_df, bg_sample)
    #return bg_sample
end


function AgentLocation2(agent::Queue, model::ABM; levee = false, f_e = 0.0, bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
    budget_reduction_perc = 0.10, penalty = 50, migrate_prob = 0.05)
    # Preallocate the DataFrame with a reasonable initial capacity
    bg_sample = DataFrame(hh_id = Int64[], bg_id = Int64[], GEOID = Int64[], cat = String[], bg_utility = Float64[])

    # Use view or filter instead of multiple list comprehensions
    moving_agents = sort!([a for a in agents_in_position(agent, model) if a isa HHAgent], by=a -> a.income, rev=true)

    # Preallocate some vectors to reduce memory allocations
    bg_ids = Vector{Int64}(undef, bg_sample_size)
    bg_GEOID = Vector{Int64}(undef, bg_sample_size)
    bg_cat = Vector{String}(undef, bg_sample_size)
    bg_utilities = Vector{Float64}(undef, bg_sample_size)

    for hh_agent in moving_agents
        # Consolidate budget selection logic
        bg_budget = if house_choice_mode == "simple_avoidance_utility"
            hh_agent.avoidance ? 
                subset(model.df, :perc_fld_area => n -> n .<= 0.10) :
                subset(model.df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true)
        elseif house_choice_mode == "budget_reduction"
            new_house_budget = hh_agent.house_budget * (1 - budget_reduction_perc)
            hh_budget = ifelse.(model.df.perc_fld_area .>= 0.10, new_house_budget, hh_agent.house_budget)
            subset(model.df, :market_value => n -> n .<= hh_budget, skipmissing=true)
        else
            subset(model.df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true, view = true)
        end

        # Use a more efficient sampling approach
        try
            # Precompute weights to avoid repeated calculations
            weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
            
            # Check for available locations more efficiently
            valid_locations = findall(weights .> 0)
            if isempty(valid_locations)
                throw(ErrorException("No affordable locations with available units"))
            end

            # Efficient sampling
            sample_size = min(length(valid_locations), bg_sample_size)
            sampled_indices = sample(abmrng(model), valid_locations, sample_size, replace=false)
            bg_options = bg_budget[sampled_indices, :]

            # More efficient way to get block group and utility information
            resize!(bg_ids, sample_size)
            resize!(bg_GEOID, sample_size)
            resize!(bg_cat, sample_size)
            resize!(bg_utilities, sample_size)

            @inbounds for (i, row) in enumerate(eachrow(bg_options))
                # Find block group more efficiently
                bg_sel = first(Iterators.filter(bg -> bg isa BlockGroup && bg.GEOID == row.GEOID, allagents(model)))
                
                bg_ids[i] = bg_sel.id
                bg_GEOID[i] = row.GEOID
                bg_cat[i] = row.income_cat
                bg_utilities[i] = getindex(getproperty(bg_sel, :current_utility), row.income_cat)
            end

            # Create move DataFrame more efficiently
            move_df = DataFrame(
                hh_id = fill(hh_agent.id, sample_size), 
                bg_id = bg_ids[1:sample_size], 
                GEOID = bg_GEOID[1:sample_size], 
                cat = bg_cat[1:sample_size], 
                bg_utility = bg_utilities[1:sample_size]
            )

            # Filter moves with higher utility
            current_utility = first(values(hh_agent.utility))
            move_df = move_df[move_df.bg_utility .> current_utility, :]

            # Check if any moves are possible
            if isempty(move_df)
                throw(ErrorException("No better locations found"))
            end

            # Append to bg_sample
            append!(bg_sample, move_df)

        catch
            # Migration logic remains similar
            if rand(abmrng(model), Binomial(1, migrate_prob)) == 1
                last_bg = model[first(keys(hh_agent.utility))]
                move_agent!(hh_agent, last_bg.pos, model)
                last_bg.occupied_units[hh_agent.group] += 1
                last_bg.available_units[hh_agent.group] -= 1
                last_bg.population += getproperty(hh_agent, :no_hhs_per_agent) * getproperty(hh_agent, :hh_size)
            else
                remove_agent!(hh_agent, model)
            end
        end
    end

    append!(model.hh_utilities_df, bg_sample)
end
"""