"""
Housing Market could probably be simplified using a group-split-combine scheme instead of iterating over agents
"""

function HousingMarket(model::ABM; market_mode = "top_candidate", bg_sample_size = 10) #start with just relocating Queue
    for market_iter in 1:bg_sample_size
        moving_agents = [id for id in reduce(vcat,ids_in_position.(getindex.(Ref(model),[0,-1]), Ref(model))) if model[id] isa HHAgent]
        #Check to see if relocating queue is empty
        if length(moving_agents) < 1
            break
        end
        bg_demand = DataFrame(top_bg = Int64[], hh_id = Int64[], hh_income = Float64[])
        for id in moving_agents

            hh_utilities_subset = model.hh_utilities_df[model.hh_utilities_df.hh_id .== id, :] #Subset hh_utilities_df based on agent choices
            sort!(hh_utilities_subset, :bg_utility, rev=true) #Sort bg candidates from highest to lowest utility
            try
                top_bg = hh_utilities_subset[market_iter, :bg_id] # get the bg name for the top candidate (excluding previous top candidates from previous iterations)
                push!(bg_demand, [top_bg, id, model[id].income]) #add bg id, agent id, and agent income to bg_demand
            catch
                #if index is out of range, means agent has gone through all affordable options
                remove_agent!(model[id], model) #remove agent
            end
        end
        #Move agents to desired bg, if possible 
        for bg in unique(bg_demand.top_bg)
            bg_subset = bg_demand[bg_demand.top_bg .== bg, :]
            if size(bg_subset)[1] >= model[bg].available_units
                #subset df further based on available space
                bg_subset = first(sort(bg_subset, :hh_income, rev=true), model[bg].available_units)
                model[bg].demand_exceeds_supply[model.tick] = true
            end

            for hh_id in bg_subset.hh_id
                #move agent to bg
                move_agent!(model[hh_id], model[bg].pos, model)
                #Update bg_id and year of residence of agent
                setproperty!(model[hh_id], :bg_id, bg)
                setproperty!(model[hh_id], :year_of_residence, model.start_year + model.tick)
                #update bg attributes
                model[bg].occupied_units += 1
                model[bg].available_units -= 1

                model[bg].population += model[hh_id].no_hhs_per_agent * model[hh_id].hh_size
            end

                #update bg occupied and available_units
            #model[bg].occupied_units += length(bg_subset[:, :hh_id])
            #model[bg].available_units -= length(bg_subset[:, :hh_id])
            
        end

    end

    #for any households remaining in queues, assume they migrate
    remove_agent!.([a for a in agents_in_position(model[0], model) if a isa HHAgent], Ref(model))
    remove_agent!.([a for a in agents_in_position(model[-1], model) if a isa HHAgent], Ref(model))
end