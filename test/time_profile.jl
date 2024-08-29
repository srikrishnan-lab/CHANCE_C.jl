
### For timing of model executions and specific evolution functions
import Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames

using BenchmarkTools

## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_levee.csv")))


#Define relevant parameters
scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 1
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


### Simple measure of model performance ###

##Performance Measure (Run 2x to account for compilation time)
b = @benchmarkable step!(balt_abm, $dummystep, $CHANCE_C.model_step!, $no_of_years) setup=(balt_abm=Simulator(default_df, balt_base, balt_levee; slr_scen = slr_scen, slr_rate = slr_rate, scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)) seconds=10 evals=1

run(b)

