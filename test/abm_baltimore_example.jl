include("../src/model_initialization.jl")

## Set input parameters 
scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 50

#List of kwargs for model properties. Variables below give the argument decription and default values.
#Changing arguments requires declaring them as inputs in the initialization function

agent_housing_aggregation = 10  # indicates the level of agent/building aggregation (e.g., 100 indicates that 1 representative agent = 100 households, 1 representative building = 100 residences)
hh_size = 2.7  # define household size (currently assumes all households have the same size, using average from 1990 data)
initial_vacancy = 0.20  # define initial vacancy for all block groups (currently assumes all block groups have same initial vacancy rate)
pop_growth_mode = "perc"  # indicates which mode of population growth is used for the model run (e.g., percent-based, exogenous time series, etc.) - currently assume constant percentage growth
pop_growth_perc = .01  # annual population percentage growth rate (only used if pop_growth_mode = 'perc')
inc_growth_mode = "random_agent_replication" # defines the mode of income growth for incoming agents (e.g., 'normal_distribution', 'percentile_based', 'random_agent_replication', etc.)
pop_growth_inc_perc = .90  # defines the income percentile for the in-migrating population (if inc_growth_mode is 'percentile_based')
inc_growth_perc = .05  # defines the increase mean incomes of the in-migrating population (if inc_growth_mode is 'normal_distribution')
bld_growth_perc = .01  # indicates the percentage of building stock increase if demand exceeds supply
perc_move = .10  # indicates the percentage of households that move each time step
perc_move_mode = "random"  # indicates the mode by which relocating households are selected (random, disutility, flood, etc.)
house_budget_mode = "rhea"  # indicates the mode by which agent's housing budget is calculated (specified percent, rhea, etc.)
house_choice_mode = "simple_avoidance_utility"  # indicates the mode of household location choice model (cobb_douglas_utility, simple_flood_utility, simple_avoidance_utility, budget_reduction)
simple_anova_coefficients = [-121428, 294707, 130553, 128990, 154887, -500000]  # coefficients for simple anova experiment [intercept, sqfeet, age, stories, baths, flood]
simple_avoidance_perc = .95  # defines the percentage of agents that avoid the flood plain
budget_reduction_perc = .90  # defines the percentage that a household reduces budget for housing good (to reserve for flood insurance costs)
stock_increase_mode = "simple_perc"  # indicates the mode in which prices increase for homes that are in high demand (simple perc, etc.)
stock_increase_perc = .05  # indicates the percentage increase in price
housing_pricing_mode = "simple_perc"
price_increase_perc = .05

### Intialize Model ###
balt_abm = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years)

### Define Model evolution ###

#Import model/agent step functions
#Import model step function
include("../src/model_evolution.jl")

"""
Order of evolution:
AgentCreation
AgentReloSampler
AgentLocation
HousingMarket
BuildingDevelopment
HousingPricing
(bg update function [for avg income])
LandscapeStatistics
"""
## The model step function and its components are recreated here for illustration purposes.
## For a typical workflow, the model step function can be declared by reading in model_evolution.jl in an `include()` statement

#Define agent steps
function agent_step!(agent::HHAgent, model::ABM)
    #Do nothing  
end
 
function agent_step!(agent::BlockGroup, model::ABM)
    ExistingAgentResampler(agent, model; model.relo_sampler...)
end
 
function agent_step!(agent::Queue, model::ABM)
    AgentLocation(agent, model; model.agent_relocate...)
end
 
function block_step!(agent::BlockGroup, model::ABM)
    BuildingDevelopment(agent, model; model.build_develop...)
    HousingPricing(agent, model; model.house_price...)
end
 
#Define model evolution
function model_step!(model::ABM)
    #Update Year
    model.tick += 1
    #clear utilities df
    empty!(model.hh_utilities_df)
    #create new agents
    NewAgentCreation(model; model.agent_creation...)
    #Determine relocating HHAgents and potential moving locations
    for id in Agents.schedule(model)
        agent_step!(model[id],model)
    end
 
    #run Housing Market to move HHAgents to desired locations
    HousingMarket(model)
 
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

### Evolve model ###
step!(balt_abm,dummystep,model_step!,no_of_years)

### Collect data during model evolution ###
include("../src/data_collect.jl")
#Note: will need to re-initiate model to run
balt_abm = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years)

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
#mdata = 

#run model
adf, _ = run!(balt_abm, dummystep, model_step!, 10; adata)


