#Import model/agent step functions
#agent
include(joinpath(dirname(@__DIR__), "agent_functions/agent_include.jl"))
#model
include(joinpath(dirname(@__DIR__), "model_functions/model_include.jl"))

#Define agent steps

"""
Executes a timestep update for a household agent.

Determines whether the household relocates based on
flood experience, risk perception, and relocation behavior.
"""
function agent_step!(agent::HHAgent, model::ABM)
    agent_prob!(agent, model; model.relo_sampler...) 
end
 
"""
Executes a timestep update for a BlockGroup agent.

Resets migration counters and updates flood exposure,
flood memory, and utility values.
"""
function agent_step!(agent::BlockGroup, model::ABM)
    #clear migrating agents Dict
    map!(x->0, values(agent.new_agents))
    flooded!(agent, model; model.flood_hazard...)
end
 
"""
Processes relocating or unassigned household agents stored in a queue.

Evaluates candidate block groups and assigns households
to new housing locations.
"""
function agent_step!(agent::Queue, model::ABM)
    AgentLocation(agent, model; model.agent_relocate...)
end
 
"""
Updates housing market conditions within a BlockGroup.

Adjusts housing prices and simulates new housing development
based on local demand and supply dynamics.
"""
function block_step!(agent::BlockGroup, model::ABM)
    HousingPricing(agent, model; model.house_price...)
    BuildingDevelopment(agent, model; model.build_develop...)
end
 
#Define model evolution

"""
Advances the agent-based model by one timestep.

Per timestep, the model:
1. Advances simulation time
2. Generates new household agents
3. Executes household relocation and flood-response behavior
4. Runs the housing market
5. Updates housing prices and development
6. Computes landscape and population statistics

Used as the primary evolution pipeline for the simulation.
"""
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
"""
Alternative model evolution pipeline with explicit location updates.

Per timestep, the model:
1. Advances simulation time
2. Generates new household agents
3. Executes household and flood dynamics
4. Updates spatial locations
5. Runs the housing market
6. Recomputes BlockGroup conditions and population totals

Differs from 'model_step!' by incorporating intermediate
'LocationUpdate' calls during evolution.
"""
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