
### For timing of model executions and specific evolution functions


using BenchmarkTools#, TimerOutputs

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames
using Agents


## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/surge_area_baltimore_levee.csv")))

### Intialize Model ###
#Define relevant parameters
model_evolve = CHANCE_C.model_step!
no_of_years = 50
perc_growth = 0.01
perc_move = 0.025
house_choice_mode = "flood_mem_utility"
flood_coef = -10.0^5
levee = false
breach = true
slr_scen = "medium" #Select SLR Scenario to use (choice of "low", "medium", and "high")
slr_rate = [3.03e-3,7.878e-3,2.3e-2] #Define SLR Rate of change for each scenario ( list order is "low", "medium", and "high")
breach_null = 0.45 
risk_averse = 0.3 
flood_mem = 10 
fixed_effect = 0

balt_abm = Simulator(default_df, balt_base, balt_levee, model_evolve; slr_scen = slr_scen, slr_rate = slr_rate, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)


### Simple measure of model performance ###

##Run once to compile functions (ignore output)
#balt_abm = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years)
@time step!(balt_abm,no_of_years)

##Actual performance measure
balt_abm = Simulator(default_df, balt_base, balt_levee, model_evolve; slr_scen = slr_scen, slr_rate = slr_rate, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)

@time step!(balt_abm,no_of_years)
