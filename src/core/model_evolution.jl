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
    ExistingAgentResampler(agent, model)
    #Do nothing  
end
 
function agent_step!(agent::BlockGroup, model::ABM)
    flooded!(agent, model; mem = model.relo_sampler[:mem])
    calc_utility(agent, model)
end

function agent_step!(agent::House, model::ABM)
    #Don Nothing
end

function block_step!(agent::BlockGroup, model::ABM)
    #BuildingDevelopment(agent, model; model.build_develop...)
    HousingPricing(agent, model; model.house_price...)
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
    for id in Agents.schedule(model)
        agent_step!(model[id],model)
    end
 
    #run Housing Market to move HHAgents to desired locations
    AgentMigration(model)
    """
    #Update BlockGroup conditions
    for id in filter!(id -> model[id] isa BlockGroup, collect(Agents.schedule(model)))
        block_step!(model[id], model)
        try
            model[id].avg_hh_income = mean([a.income for a in agents_in_position(model[id].pos, model) if a isa HHAgent])
        catch  #if not incomes_bg:  # i.e. no households reside in block group
            model[id].avg_hh_income = NaN
        end
         
    end
    """
    LandscapeStatistics(model)
    model.total_population = sum([a.population for a in allagents(model) if a isa HHAgent])
end