## Update Flooded Houses
function flooded!(agent::BlockGroup, model::ABM; mem = 10, levee = false, f_e = 0.0, flood_coef = 500000, penalty = 50)
    
    year = model.tick
    ##Record number of floods in the last mem years
    #determine current time interval and retrieve flood record from interval
    time_back = year > mem ? range(year, year - (mem-1), step = -1) : range(year, 1, step = -1)
    flood_mem = get.(Ref(model.flood_dict),collect(time_back), Ref("Record not present"))

    #subset flood matrix using flood record and sum the total flood area from events experienced
    flood_events = [model.flood_matrix.hazard[agent.id, rp, breach] for (breach,rp) in flood_mem]
    flood_norm_events = [model.flood_matrix.norm[agent.id, rp, breach] for (breach,rp) in flood_mem]
    agent.flood_hazard = sum(flood_events)/mem #Calculate avg. flood per year in flood mem window

    ##Utility Updating
    #Determine if flood disamenity is reduced from levee presence
    scale_factor = levee ? 1.0 - (10 * f_e) : 1.0
    #Update Utilities with new flood hazard 
    norm_events = sum(flood_norm_events)/mem
    util_update = (scale_factor * flood_coef * (norm_events))

    bg_df = filter(row -> row.GEOID == agent.GEOID, model.df, view=true)
    
    agent.current_utility = agent.base_utility .- util_update
    for col in 1:size(agent.current_utility,2)
        bg_df[col, :curr_utility] = agent.current_utility[:,col]
    end
    

    ## For HHAgents within Blockgroup
    #Collect HHAgent ids within BlockGroup
    hh_ids = collect([hh.id for hh in agents_in_position(agent, model) if hh isa HHAgent])
    for hh_id in hh_ids
        #Add flood event to agent hazard vector
        model[hh_id].flood_hazard[year] = flood_events[1]
        #Calculate remembered flood experience
        model[hh_id].flood_experience = sum(model[hh_id].flood_hazard[time_back])/mem
        #Update HHagent utility
        model[hh_id].utility[agent.id] = agent.current_utility[model[hh_id].group, model[hh_id].occ_cat]
    end  
end
