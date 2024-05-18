#
#
using Agents
## Agent Filtering
#Filter by BGs in/out floodplain
BG(agent) = agent isa BlockGroup
f_bgs(agent) = agent isa BlockGroup && agent.perc_fld_area > 0.10
nf_bgs(agent) = agent isa BlockGroup && agent.perc_fld_area <= 0.10

#Count HHAgents in BG
bg_pop(agent) = length([a for a in agents_in_position(agent, model) if a isa HHAgent])

##Population
#Calculate population density for BG
pop_den(agent) = agent.population / agent.area

#Calculate population change for BG
pop_change(agent) = (agent.population - agent.pop90) / agent.pop90

#get income
bg_inc(agent) = sum([a.income for a in agents_in_position(agent, model) if a isa HHAgent])

#get average house price 
avg_price(agent) = agent.new_price * agent.population