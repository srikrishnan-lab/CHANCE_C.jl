"""
Housing Market could probably be simplified using a group-split-combine scheme instead of iterating over agents
"""

function HousingMarket(model::ABM; market_mode = "top_candidate", bg_sample_size = 10, stay_prob = 1.0) #start with just relocating Queue
    for market_iter in 1:bg_sample_size
        moving_agents = [id for id in ids_in_position(model[0], model) if model[id] isa HHAgent]
        #Check to see if relocating queue is empty
        if length(moving_agents) < 1
            break
        end
        bg_demand = DataFrame(top_bg = Int64[], top_cat = Int64[], hh_id = Int64[], hh_income = Float64[], hh_util = Float64[])

        for id in moving_agents
            hh_utilities_subset = model.hh_utilities_df[model.hh_utilities_df.hh_id .== id, :] #Subset hh_utilities_df based on agent choices
            sort!(hh_utilities_subset, :bg_utility, rev=true) #Sort bg candidates from highest to lowest utility
            try
                top_bg = hh_utilities_subset[market_iter, :bg_id] # get the bg name for the top candidate (excluding previous top candidates from previous iterations)
                top_cat = hh_utilities_subset[market_iter, :cat] # get the category name of bg for the top candidate (excluding previous top candidates from previous iterations)
                top_util = hh_utilities_subset[market_iter, :bg_utility] # get the agent utility of bg for the top candidate (includes penalty for category mismatch)
                push!(bg_demand, [top_bg, top_cat, id, model[id].income, top_util]) #add bg id, house category, agent id, agent income, and agent utility to bg_demand
            catch
                #if index is out of range, means agent has gone through all affordable options
                last_bg = model[first(keys(model[id].utility))]
                if last_bg.id == -1 || last_bg.available_units[model[id].occ_cat] <= 0
                    remove_agent!(model[id], model)
                    continue
                end
                    
                if rand(abmrng(model), Binomial(1, stay_prob)) == 1
                    #Revert HHAgent Properties
                    setproperty!(model[id], :bg_id, last_bg.id)
                    move_agent!(model[id], last_bg.pos, model)
                    #Update Last BG Properties
                    last_bg.occupied_units[model[id].occ_cat] += 1
                    last_bg.available_units[model[id].occ_cat] -= 1
                    last_bg.population += getproperty(model[id], :no_hhs_per_agent) * getproperty(model[id], :hh_size)
                else
                    remove_agent!(model[id], model)
                end
            end
        end
        #Move agents to desired bg, if possible 
        for (bg_id, cat) in eachrow(unique!(select(bg_demand, [:top_bg, :top_cat])))
            bg_subset = bg_demand[(bg_demand.top_bg .== bg_id) .& (bg_demand.top_cat .== cat), :]
            model[bg_id].demand_exceeds_supply[cat][model.tick] = nrow(bg_subset) - model[bg_id].available_units[cat]
            if nrow(bg_subset) >= model[bg_id].available_units[cat]
                #subset df further based on available space
                bg_subset = first(sort(bg_subset, :hh_income, rev=true), model[bg_id].available_units[cat])
            end

            for hh_id in bg_subset.hh_id
                #move agent to bg
                move_agent!(model[hh_id], model[bg_id].pos, model)
                #Update bg_id, utility,  year of residence of agent
                setproperty!(model[hh_id], :bg_id, bg_id)
                setproperty!(model[hh_id], :occ_cat, cat)
                setproperty!(model[hh_id], :utility, Dict(bg_id => bg_demand[(bg_demand.hh_id .== hh_id) .& (bg_demand.top_bg .== bg_id) .& (bg_demand.top_cat .== cat), :hh_util][1]))#Dict(bg_id => model[bg_id].current_utility[cat]))
                setproperty!(model[hh_id], :year_of_residence, model.tick)
                #update bg attributes
                model[bg_id].occupied_units[cat] += 1
                model[bg_id].available_units[cat] -= 1

                model[bg_id].population += getproperty(model[hh_id],:no_hhs_per_agent) * getproperty(model[hh_id],:hh_size)
            end
            
        end

    end

    #for any households remaining in queues, assume they migrate
    for a in collect(agents_in_position(model[0], model)) 
        if a isa HHAgent
            last_bg = model[first(keys(a.utility))]
            if last_bg.id == -1 || last_bg.available_units[a.occ_cat] <= 0
                remove_agent!(a, model)
                continue
            end
            
            if rand(abmrng(model), Binomial(1, stay_prob)) == 1
                #Revert HHAgent Properties
                setproperty!(a, :bg_id, last_bg.id)
                move_agent!(a, last_bg.pos, model)
                #Update Last BG Properties
                last_bg.occupied_units[a.occ_cat] += 1
                last_bg.available_units[a.occ_cat] -= 1
                last_bg.population += getproperty(a, :no_hhs_per_agent) * getproperty(a, :hh_size)
            else
                remove_agent!(a, model)
            end
        else
            continue
        end
    end
end


##Create new HousingMarket mechanism
function HouseMarket(model::ABM; market_mode = "top_candidate", bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
    budget_reduction_perc = 0.10, stay_prob = 1.0, grouped=true)
    ## Collect characteristics of all locations. Sort by utility value
    loc_df = sort!(copy(model.df), :curr_utility, rev=true)
    loc_df[!,:demand] = zeros(nrow(loc_df))
    # Create a GEOID-to-BlockGroup lookup
    geoid_to_bg = Dict{Int64, Int64}()
    for bg in allagents(model)
        if bg isa BlockGroup
            geoid_to_bg[bg.GEOID] = bg.id
        end
    end
    ##For each moving agent:
    moving_agents = sort!([a for a in ids_in_position(model[0], model) if model[a] isa HHAgent], by=a -> model[a].income, rev=true)
    for ma in moving_agents
        #Subset to affordable and desirable locations
        bg_budget = if house_choice_mode == "simple_avoidance_utility"
                        hh_agent.avoidance ? 
                            subset(loc_df, :perc_fld_area => n -> n .<= 0.10, view = true) :
                            subset(loc_df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true, view = true)
                    elseif house_choice_mode == "budget_reduction"
                        new_house_budget = hh_agent.house_budget * (1 - budget_reduction_perc)
                        hh_budget = ifelse.(loc_df.perc_fld_area .>= 0.10, new_house_budget, hh_agent.house_budget)
                        subset(loc_df, :market_value => n -> n .<= hh_budget, skipmissing=true, view = true)
                    else
                        subset(loc_df, :market_value => n -> n .<= model[ma].house_budget,
                         [:curr_utility, :income_cat] => ((c,i) -> getindex.(c, model[ma].group) .>= first(values(model[ma].utility))),
                          skipmissing=true, view = true)
                    end
        #find first location with vacancy
        loc_ind = findfirst(x -> x > 0, bg_budget.available_units)
        #If there are no location options, agent moves back or outmigrates
        if isnothing(loc_ind)
            last_bg = model[first(keys(model[ma].utility))]
            if grouped
                if last_bg.id == -1 || last_bg.available_units[model[ma].occ_cat] <= 0
                    remove_agent!(model[ma], model)
                    continue
                end
                    
                if rand(abmrng(model), Binomial(1, stay_prob)) == 1
                    #Revert HHAgent Properties
                    setproperty!(model[ma], :bg_id, last_bg.id)
                    move_agent!(model[ma], last_bg.pos, model)
                    #Update Last BG Properties
                    last_bg.occupied_units[model[ma].occ_cat] += 1
                    last_bg.available_units[model[ma].occ_cat] -= 1
                    last_bg.population += getproperty(model[ma], :no_hhs_per_agent) * getproperty(model[ma], :hh_size)
                    continue
                else
                    remove_agent!(model[ma], model)
                    continue
                end
            else
                if last_bg.id == -1 || last_bg.available_units <= 0
                    remove_agent!(model[ma], model)
                    continue
                end
                    
                if rand(abmrng(model), Binomial(1, stay_prob)) == 1
                    #Revert HHAgent Properties
                    setproperty!(model[ma], :bg_id, last_bg.id)
                    move_agent!(model[ma], last_bg.pos, model)
                    #Update Last BG Properties
                    last_bg.occupied_units += 1
                    last_bg.available_units -= 1
                    last_bg.population += getproperty(model[ma], :no_hhs_per_agent) * getproperty(model[ma], :hh_size)
                    continue
                else
                    remove_agent!(model[ma], model)
                    continue
                end
            end
        end
        #Get characteristics of block group
        last_bg_id = model[first(keys(model[ma].utility))].id
        new_bg_id = geoid_to_bg[bg_budget[loc_ind,:GEOID]]
        occ_cat = bg_budget[loc_ind,:income_cat]
        new_util = bg_budget[loc_ind, :curr_utility][model[ma].group] 
        
        #Move agent to new location
        move_agent!(model[ma], model[new_bg_id].pos, model)
        #Update bg_id, utility,  year of residence of agent
        setproperty!(model[ma], :bg_id, new_bg_id)
        setproperty!(model[ma], :occ_cat, occ_cat)
        setproperty!(model[ma], :utility, Dict(new_bg_id => new_util)) #Dict(bg_id => model[bg_id].current_utility[cat]))
        setproperty!(model[ma], :year_of_residence, model.tick)
        #update bg attributes
        model[new_bg_id].occupied_units[occ_cat] += 1
        model[new_bg_id].available_units[occ_cat] -= 1              
        model[new_bg_id].population += getproperty(model[ma],:no_hhs_per_agent) * getproperty(model[ma],:hh_size)
        #If moving agent is in-migrating, record in migrating agent dict
        if last_bg_id == -1
            model[new_bg_id].new_agents[model[ma].group] += 1
        end


        bg_budget[loc_ind, :available_units] -= 1
        #increase the interest count for all selections
        bg_budget[!, :demand] .+= 1
    end
    
    #Update demand attributes for all BlockGroups 
    for row in eachrow(loc_df)
        model[geoid_to_bg[row.GEOID]].demand_exceeds_supply[row.income_cat][model.tick] = row.demand - row.available_units
    end

end