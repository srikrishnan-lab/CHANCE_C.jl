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
    agent_prob!(agent, model; model.relo_sampler...) 
end
 
function agent_step!(agent::BlockGroup, model::ABM)
    #clear migrating agents Dict
    map!(x->0, values(agent.new_agents))
    flooded!(agent, model; model.flood_hazard...)
end
 
function agent_step!(agent::Queue, model::ABM)
    AgentLocation(agent, model; model.agent_relocate...)
end
 
function block_step!(agent::BlockGroup, model::ABM)
    HousingPricing(agent, model; model.house_price...)
    BuildingDevelopment(agent, model; model.build_develop...)
end
 
#Define model evolution
function model_step!(model::ABM)
    #Update Year
    model.tick += 1
    #clear utilities df
    empty!(model.hh_utilities_df)
    #create new agents
    AgentMigration(model; model.agent_creation...)
    #Determine relocating HHAgents and potential moving locations
    for id in collect(Agents.schedule(model))
        if model[id] isa HHAgent && model[id].bg_id < 1 #Dont involve HHAgents in Queues
            continue
        else
            agent_step!(model[id],model)
        end
    end
 
    #run Housing Market to move HHAgents to desired locations
    HousingMarket(model;model.hh_market...)
 
    #Update BlockGroup conditions
    for id in filter!(id -> model[id] isa BlockGroup, collect(Agents.schedule(model)))
        block_step!(model[id], model)
        try
            model[id].avg_hh_income = mean([a.income for a in agents_in_position(model[id].pos, model) if a isa HHAgent])
        catch  #if not incomes_bg:  # i.e. no households reside in block group
            model[id].avg_hh_income = NaN
        end
         
    end
    LandscapeStatistics(model)
    model.total_population = sum([a.population for a in allagents(model) if a isa BlockGroup])
end




#Define alternate model evolution
function evolve!(model::ABM)
    #Update Year
    model.tick += 1
    #clear utilities df
    empty!(model.hh_utilities_df)
    #create new agents
    AgentMigration(model; model.agent_creation...)
    #Determine relocating HHAgents and potential moving locations
    for id in collect(Agents.schedule(model))
        if model[id] isa HHAgent && model[id].bg_id < 1 #Dont involve HHAgents in Queues
            continue
        elseif model[id] isa Queue
            continue
        else
            agent_step!(model[id],model)
        end
    end
    LocationUpdate(model)
    #run Housing Market to move HHAgents to desired locations
    HouseMarket(model; model.hh_market...)

    #Update BlockGroup conditions
    for id in filter!(id -> model[id] isa BlockGroup, collect(Agents.schedule(model)))
        block_step!(model[id], model)
        try
            model[id].avg_hh_income = mean([a.income for a in agents_in_position(model[id].pos, model) if a isa HHAgent])
        catch  #if not incomes_bg:  # i.e. no households reside in block group
            model[id].avg_hh_income = NaN
        end

    end
    LocationUpdate(model)
    model.total_population = sum([a.population for a in allagents(model) if a isa BlockGroup])
end