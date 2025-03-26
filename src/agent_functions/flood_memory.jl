## Update Flooded Houses
function flooded!(agent::BlockGroup, model::ABM; mem = 10, levee = false, f_e = 0.0, flood_coef = -500000)
    
    year = model.tick
    ##Record number of floods in the last mem years
    #determine current time interval and retrieve flood record from interval
    time_back = year > mem ? range(year, year - (mem-1), step = -1) : range(year, 1, step = -1)
    flood_mem = get.(Ref(model.flood_dict),collect(time_back), Ref("Record not present"))

    #subset flood matrix using flood record and sum the total flood area from events experienced
    flood_events = [model.flood_matrix[agent.id, rp, breach] for (breach,rp) in flood_mem]
    agent.flood_hazard = sum(flood_events)

    ##Utility Updating
    #Determine if flood disamenity is reduced from levee presence
    scale_factor = levee ? 1.0 - (10 * f_e) : 1.0
    #Update Utilities with new flood hazard 
    util_update = (scale_factor * flood_coef * (agent.flood_hazard/mem))
    for key in keys(agent.current_utility)
        agent.current_utility[key] = agent.base_utility[key] + util_update
    end

    ## For HHAgents within Blockgroup
    #Collect HHAgent ids within BlockGroup
    hh_ids = collect([hh.id for hh in agents_in_position(agent, model) if hh isa HHAgent])
    for hh_id in hh_ids
        #Add flood event to agent hazard vector
        model[hh_id].flood_hazard[year] = flood_events[1]
        #Calculate remembered flood experience
        model[hh_id].flood_experience = sum(model[hh_id].flood_hazard[time_back])
        #Update HHagent utility
        model[hh_id].utility[agent.id] = agent.current_utility[model[hh_id].group]
    end  
end
