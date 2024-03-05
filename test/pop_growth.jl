### Check to see if model population is growing over time ###
#Want to make sure that HHagents aren't removed prematurely

include("../src/model_initialization.jl")
#Import model step function
include("../src/model_evolution.jl")
#Collect data during model evolution
include("../src/data_collect.jl")

## Set input parameters 
scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 50

## For avoidance 
model = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years, simple_avoidance_perc = 0.95)
orig_pop = nagents(model) - 1222

##First agent step
model.tick += 1
#create new agents
NewAgentCreation(model; model.agent_creation...)

#Check pop. Make sure it aligns with growth rate 
new_pop = nagents(model) - 1222 
fld((((model.total_population * model.agent_creation[:growth_rate]) / model.agent_creation[:hh_size]) + fld(model.agent_creation[:no_hhs_per_agent], 2)), 
model.agent_creation[:no_hhs_per_agent]) == new_pop - orig_pop

#Determine relocating HHAgents and potential moving locations
for id in filter!(id -> model[id] isa BlockGroup, collect(Agents.schedule(model)))
    agent_step!(model[id],model)
end

#Check pop 
nagents(model) - 1222

#run Agent relocation
AgentLocation(model[0], model; model.agent_relocate...)
AgentLocation(model[-1], model; model.agent_relocate...)

"""
hh_agent = collect(agents_in_position(model[0], model))[2]

   

if hh_agent.avoidance
    bg_budget = subset(model.df, :perc_fld_area => n -> n .<= 0.10) #does new_price <= house_budget?
else
    bg_budget = subset(model.df, :new_price => n -> n .<= hh_agent.house_budget)
end

weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
bg_options = bg_budget[sample(model.rng, 1:nrow(bg_budget), weights, 10; replace = true), :] #need to add weights based on available_units column
#Calculate utility of options for household agents
bg_utilities = calc_utility.(eachrow(bg_options), "simple_avoidance_utility"; anova_coef = [-121428, 294707, 130553, 128990, 154887, -500000])
"""

##run Housing Market to move HHAgents to desired locations ##
#Number of moving agents 
length([id for id in reduce(vcat,ids_in_position.(getindex.(Ref(model),[0,-1]), Ref(model))) if model[id] isa HHAgent])

HousingMarket(model)

#Check pop 
nagents(model) - 1222