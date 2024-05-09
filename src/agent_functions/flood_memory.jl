## Update Flooded Houses
function flooded!(agent::BlockGroup, model::ABM; mem = 10)
    year = model.tick
    ##Record number of floods in the last mem years
   
    #determine current time interval and retrieve flood record from interval
    time_back = year > mem ? range(year, year - (mem-1), step = -1) : range(year, 1, step = -1)
    flood_mem = get.(Ref(model.flood_dict),collect(time_back), Ref("Record not present"))

    #subset flood matrix using flood record and sum the total flood area from events experienced
    flood_events = [model.flood_matrix[agent.id, rp, breach] for (breach,rp) in flood_mem]
    agent.flood_hazard = sum(flood_events)
end
