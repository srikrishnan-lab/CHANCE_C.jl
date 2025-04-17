"""
Housing Market could probably be simplified using a group-split-combine scheme instead of iterating over agents
"""

function HousingMarket(model::ABM; market_mode = "top_candidate", bg_sample_size = 10) #start with just relocating Queue
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
                remove_agent!(model[id], model) #remove agent
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
    remove_agent!.([a for a in agents_in_position(model[0], model) if a isa HHAgent], Ref(model))
end