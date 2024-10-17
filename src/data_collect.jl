
using Agents
## Agent Filtering
#Filter by BGs in/out floodplain
BG(agent) = agent isa BlockGroup
f_bgs(agent) = agent isa BlockGroup && agent.perc_fld_area > 0
nf_bgs(agent) = agent isa BlockGroup && agent.perc_fld_area == 0

#Count HHAgents in BG
bg_pop(agent) = length([a for a in agents_in_position(agent, model) if a isa HHAgent])

#Count HHAgents trying to move each year
Rel(agent) = agent isa Queue && agent.type == :relocating
Un(agent) = agent isa Queue && agent.type == :unassigned
move_pop(agent) = length([a for a in agents_in_position(agent, model) if a isa HHAgent])
##Population
#Calculate population density for BG
pop_den(agent) = agent.population / agent.area

#Calculate population change for BG
pop_change(agent) = (agent.population - agent.pop90) / agent.pop90

#get income
bg_inc(agent) = sum([a.income for a in agents_in_position(agent, model) if a isa HHAgent])

<<<<<<< HEAD
##
#Grab surge events at each time step
function flood_record(model::ABM)
    if model.tick == 0
        return 0.0
    else
        surge_range = collect(0.5:0.25:4)
        breach, rp = model.flood_dict[model.tick]
        return surge_range[rp]
    end
end

#Grab intervention scenario at each time step
function flood_scenario(model::ABM)
    if model.tick == 0
        return 0.0
    else
        breach, rp = model.flood_dict[model.tick]
        return breach
    end
end

#Calculate total flood area at each time step
function total_fld_area(model::ABM)
    if model.tick == 0
        return 0.0
    else
        breach, rp = model.flood_dict[model.tick]
        fld_area = sum(model.flood_matrix[:, rp, breach])
        return fld_area
    end
end
=======
#get average house price 
avg_price(agent) = agent.new_price * agent.population
>>>>>>> main
