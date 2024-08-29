import Pkg
Pkg.activate(".")
Pkg.instantiate()

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames



## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/surge_area_baltimore_levee.csv")))

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
#Define relevant parameters
model_evolve = CHANCE_C.model_step!
no_of_years = 10
perc_growth = 0.01
perc_move = 0.025
house_choice_mode = "flood_mem_utility"
flood_coef = -10.0^5
levee = false
breach = true
slr_scen = "high" #Select SLR Scenario to use (choice of "low", "medium", and "high")
slr_rate = [3.03e-3,7.878e-3,2.3e-2] #Define SLR Rate of change for each scenario ( list order is "low", "medium", and "high")
breach_null = 0.45 
risk_averse = 0.3 
flood_mem = 10 
fixed_effect = 0


balt_abm = Simulator(default_df, balt_base, balt_levee, model_evolve; slr_scen = slr_scen, slr_rate = slr_rate, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)

### Define Model evolution ###
"""
Order of evolution:
AgentCreation
Flooded
agent_prob
AgentLocation
HousingMarket
BuildingDevelopment
HousingPricing
(bg update function [for avg income])
LandscapeStatistics
"""

### Evolve model ###
step!(balt_abm,dummystep,CHANCE_C.model_step!,no_of_years)

### Collect data during model evolution ###
include(joinpath(dirname(@__DIR__), "src/data_collect.jl"))

#Note: will need to re-initiate model to run
balt_abm = Simulator(default_df, balt_base, balt_levee; slr_scen = slr_scen, slr_rate = slr_rate, scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
#mdata = 

#run model
adf, _ = run!(balt_abm, dummystep, CHANCE_C.model_step!, 10; adata)


