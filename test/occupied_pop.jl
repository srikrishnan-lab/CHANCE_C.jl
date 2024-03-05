"Test case to ensure occupied units correspond with total bg population"

balt_abm = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years)

test_occ(agent) = agent.occupied_units != length[a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]


"""
#BG of interest
bg_i = balt_abm[1218]
no_of_hhs = round(bg_i.pop90 / median(skipmissing(balt_abm.df.hhsize1990)))
no_of_agents = fld(fld(no_of_hhs + 10, 2), 10)

bg_i.occupied_units
#length(collect(agents_in_position(bg_i, balt_abm)))

length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent])

no_of_yrs = 2

for _ in 1:no_of_yrs
    #Update Year
    balt_abm.tick += 1

    #Determine relocating HHAgents and potential moving locations
    #agent_step!(bg_i, balt_abm)
    for id in Agents.schedule(balt_abm)
        agent_step!(balt_abm[id],balt_abm)
    end
    println("agent_step")
    println(bg_i.occupied_units)

    println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))
    
    #run Housing Market to move HHAgents to desired locations
    HousingMarket(balt_abm)

    println("HousingMarket")
    println(bg_i.occupied_units)

    println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))

    #Update BlockGroup conditions
    for id in filter!(id -> balt_abm[id] isa BlockGroup, collect(Agents.schedule(balt_abm)))
        block_step!(balt_abm[id], balt_abm)
        try
            balt_abm[id].avg_hh_income = mean([a.income for a in agents_in_position(balt_abm[id].pos, balt_abm) if a isa HHAgent])
        catch  #if not incomes_bg:  # i.e. no households reside in block group
            balt_abm[id].avg_hh_income = NaN
        end
        
    end
    println("BG Update")
    println(bg_i.occupied_units)

    println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))

    LandscapeStatistics(balt_abm)

    println("LandscapeStatistics")
    println(bg_i.occupied_units)

    println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))
    
end

step!(balt_abm, dummystep, model_step!, 10)

println(bg_i.occupied_units)

println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))




#Issue with Housing Market
for id in Agents.schedule(balt_abm)
    agent_step!(balt_abm[id],balt_abm)
end

println(bg_i.occupied_units)
println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))


for market_iter in 1:10
    println("market_iter $market_iter")
    moving_agents = [id for id in ids_in_position(balt_abm[0], balt_abm) if balt_abm[id] isa HHAgent]
    #Check to see if relocating queue is empty
    if length(moving_agents) < 1
        break
    end
    bg_demand = DataFrame(top_bg = Int64[], hh_id = Int64[], hh_income = Float64[])
    for id in moving_agents

        hh_utilities_subset = balt_abm.hh_utilities_df[balt_abm.hh_utilities_df.hh_id .== id, :] #Subset hh_utilities_df based on agent choices
        sort!(hh_utilities_subset, :bg_utility, rev=true) #Sort bg candidates from highest to lowest utility
        try
            top_bg = hh_utilities_subset[market_iter, :bg_id] # get the bg name for the top candidate (excluding previous top candidates from previous iterations)
            push!(bg_demand, [top_bg, id, balt_abm[id].income]) #add bg id, agent id, and agent income to bg_demand
        catch
            #if index is out of range, means agent has gone through all affordable options
            remove_agent!(balt_abm[id], balt_abm) #remove agent
        end
    end
    println(bg_i.occupied_units)

    println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))
    

    #Move agents to desired bg, if possible 
    for bg in unique(bg_demand.top_bg)
        bg_subset = bg_demand[bg_demand.top_bg .== bg, :]
        if size(bg_subset)[1] >= balt_abm[bg].available_units
            #subset df further based on available space
            bg_subset = first(sort(bg_subset, :hh_income, rev=true),balt_abm[bg].available_units)
            balt_abm[bg].demand_exceeds_supply[balt_abm.tick] = true
        end
        #println(bg_i.occupied_units)

        #println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))

        for hh_id in bg_subset.hh_id
            #move agent to bg
            move_agent!(balt_abm[hh_id], balt_abm[bg].pos, balt_abm)
            #Update bg_id and year of residence of agent
            setproperty!(balt_abm[hh_id], :bg_id, bg)
            setproperty!(balt_abm[hh_id], :year_of_residence, balt_abm.start_year + model.tick) 
        end
       

            #update bg occupied and available_units
        balt_abm[bg].occupied_units += length(bg_subset[:, :hh_id])
        balt_abm[bg].available_units -= length(bg_subset[:, :hh_id])
        


    end
    println(bg_i.occupied_units)

    println(length([a for a in agents_in_position(bg_i, balt_abm) if a isa HHAgent]))

end

"""

