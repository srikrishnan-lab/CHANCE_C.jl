"""
Defines model step function by combining individual agent and model evolution functions
"""
#Import model/agent step functions
#agent
include(joinpath(dirname(@__DIR__), "agent_functions/agent_include.jl"))
#model
include(joinpath(dirname(@__DIR__), "model_functions/model_include.jl"))

#Define agent steps
function agent_step!(agent::HHAgent, model::ABM)
    #Do nothing  
end
 
function agent_step!(agent::BlockGroup, model::ABM)
    flooded!(agent, model; mem = model.relo_sampler[:mem])
    AgentMove!(agent, model; model.relo_sampler...)
    calc_utility(agent, model)
end

function agent_step!(agent::House, model::ABM)
    #Don Nothing
end

function block_step!(agent::BlockGroup, model::ABM)
    #BuildingDevelopment(agent, model; model.build_develop...)
    #HousingPricing(agent, model; model.house_price...)
    agent.population = sum([a.population for a in agents_in_position(agent, model) if a isa HHAgent])
    agent.occupied_units = sum([a.occupied_units for a in agents_in_position(agent, model) if a isa House])
    agent.available_units = sum([a.available_units for a in agents_in_position(agent, model) if a isa House])

end

function block_step!(agent::House, model::ABM)
    BuildingDevelopment(agent, model; model.build_develop...)
    HousingPricing(agent, model; model.house_price...)

end

function block_step!(agent::HHAgent, model::ABM)
    #Do Nothing

end
 

#Define model evolution
function model_step!(model::ABM)
    #Update Year
    model.tick += 1
    #clear utilities 
    fill!(model.hh_utilities, 0.0)
    #create new agents
    #NewAgentCreation(model; model.agent_creation...)
    #Determine relocating HHAgents and potential moving locations
    for id in collect(Agents.schedule(model))
        agent_step!(model[id],model)
    end
 
    #run Housing Market to move HHAgents to desired locations
    AgentMigration(model; growth_rate = model.agent_creation[:growth_rate], hh_size = 2.7, no_hhs_per_agent = 10)
    
    #Update BlockGroup conditions
    for id in collect(Agents.schedule(model))
        block_step!(model[id], model)
    end
    
    LandscapeStatistics(model)
    model.total_population = sum([a.population for a in allagents(model) if a isa HHAgent])
end